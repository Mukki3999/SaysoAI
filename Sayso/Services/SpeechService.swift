import AVFoundation
import Speech
import Observation

enum SpeechError: LocalizedError {
    case permissionDenied(String)
    case unsupportedLocale
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let what): "Sayso needs \(what) access to hear you."
        case .unsupportedLocale: "On-device speech isn't available for your language yet."
        case .noSpeech: "Didn't catch that."
        }
    }
}

/// Push-to-talk transcription with SpeechAnalyzer. SpeechTranscriber runs fully on-device,
/// so there is no server fallback to turn off.
@MainActor @Observable
final class SpeechService {
    private(set) var transcript = ""
    private(set) var level: Double = 0
    private(set) var isListening = false
    private(set) var permissionDenied = false

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""

    // MARK: Permissions (lazy, first talk)

    private func ensurePermissions() async throws {
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { permissionDenied = true; throw SpeechError.permissionDenied("microphone") }
        let status = await Self.requestSpeechAuthorization()
        guard status == .authorized else { permissionDenied = true; throw SpeechError.permissionDenied("speech recognition") }
        permissionDenied = false
    }

    /// Nonisolated: the system calls back on a background queue, which traps in a MainActor closure.
    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }

    // MARK: Start / stop

    func start() async throws {
        guard !isListening else { return }
        try await ensurePermissions()

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw SpeechError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // Asking for the install request is what subscribes this app to the locale's assets,
        // so it has to come before any status check.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        _ = try await AssetInventory.reserve(locale: locale)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechError.unsupportedLocale
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        finalized = ""; volatile = ""; transcript = ""

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.apply(text: text, isFinal: result.isFinal)
                }
            } catch {}
        }

        do {
            installTap(format: format, continuation: continuation)
            engine.prepare()
            try engine.start()
            try await analyzer.start(inputSequence: stream)
            isListening = true
        } catch {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            continuation.finish()
            resultsTask?.cancel()
            await analyzer.cancelAndFinishNow()
            self.analyzer = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    /// Stops capture and returns the final transcript.
    @discardableResult
    func stop() async -> String {
        guard isListening else { return transcript }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        analyzer = nil
        resultsTask = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        transcript = (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript
    }

    func cancel() async {
        guard isListening else { return }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        analyzer = nil
        level = 0
        transcript = ""
    }

    // MARK: Internals

    private func apply(text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
        transcript = (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func installTap(format target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        Self.installTap(on: engine.inputNode, target: target, continuation: continuation) { [weak self] rms in
            Task { @MainActor in self?.level = rms }
        }
    }

    /// Nonisolated so the tap closure runs on the audio thread without a MainActor check.
    private nonisolated static func installTap(on input: AVAudioInputNode, target: AVAudioFormat,
                                               continuation: AsyncStream<AnalyzerInput>.Continuation,
                                               onLevel: @escaping @Sendable (Double) -> Void) {
        let hw = input.outputFormat(forBus: 0)
        let converter = BufferConverter(from: hw, to: target)
        input.installTap(onBus: 0, bufferSize: 2048, format: hw) { buffer, _ in
            onLevel(rms(of: buffer))
            if let out = converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: out))
            }
        }
    }

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let value = sqrt(sum / Float(buffer.frameLength))
        return min(1, Double(value) * 8)
    }
}

/// Wraps AVAudioConverter so the audio-thread tap closure can use it.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat

    init(from source: AVAudioFormat, to target: AVAudioFormat) {
        self.target = target
        self.converter = source == target ? nil : AVAudioConverter(from: source, to: target)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let input = buffer
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        return error == nil ? out : nil
    }
}
