import AVFoundation
import CoreML
import KokoroTTS
import Network
import NaturalLanguage
import Observation

/// Sayso's own voice: an open-source neural voice model (Kokoro, Apache-2.0) that runs on the iPhone.
/// It downloads once in the background, on Wi-Fi, and nothing the user says or hears ever leaves the phone.
/// Until it is ready, and if anything goes wrong, Apple's built-in voice speaks instead.
@MainActor @Observable
final class NeuralVoice {
    enum State: Equatable { case idle, downloading(Double), ready, failed(String) }

    static let shared = NeuralVoice()
    private(set) var state: State = .idle
    var isReady: Bool { state == .ready }

    private let engine = VoiceEngine()
    private let player = VoicePlayer()
    private var speakTask: Task<Void, Never>?
    private var preparing = false

    /// Starts the one-time download if it hasn't happened. Skips cellular and Low Data Mode: it can wait for Wi-Fi.
    func prepare() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SAYSO_TEST_VOICE"] == "1" { return }   // the self-test does its own download
        #endif
        guard !preparing, state == .idle || { if case .failed = state { true } else { false } }() else { return }
        preparing = true
        Task {
            defer { preparing = false }
            guard await Self.onUnmeteredNetwork() || VoiceEngine.isDownloaded else { state = .idle; return }
            state = .downloading(0)
            do {
                try await engine.load { fraction in
                    Task { @MainActor in NeuralVoice.shared.state = .downloading(fraction) }
                }
                state = .ready
            } catch {
                state = .failed(String(describing: error).prefix(160).description)
            }
        }
    }

    /// Speaks sentence by sentence, so the first words start while the rest is still being made.
    func speak(_ text: String, onFinish: @escaping () -> Void = {}) {
        stop()
        let sentences = Self.sentences(of: SpeechText.clean(text))
        guard !sentences.isEmpty else { onFinish(); return }
        let player = self.player
        let engine = self.engine
        speakTask = Task {
            player.begin()
            for sentence in sentences {
                if Task.isCancelled { return }
                guard let samples = try? await engine.synthesize(sentence), !samples.isEmpty else { continue }
                if Task.isCancelled { return }
                player.enqueue(samples)
            }
            await player.drain()
            if !Task.isCancelled { onFinish() }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        player.stop()
    }

    var isSpeaking: Bool { player.isPlaying }

    static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
            return true
        }
        return out
    }

    private static func onUnmeteredNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let gate = Gate()
            monitor.pathUpdateHandler = { path in
                guard gate.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            monitor.start(queue: DispatchQueue(label: "sayso.voice.net"))
        }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }
}

/// Owns the Core ML model. Synthesis runs off the main thread.
actor VoiceEngine {
    private var model: KokoroTTSModel?
    private static let voice = "af_heart"
    /// The 8-bit build: about 82 MB instead of 312 MB, and still a natural voice.
    private static let modelId = "aufklarer/Kokoro-82M-CoreML-INT8"

    static var cacheDir: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Sayso/voice-int8", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true            // a re-downloadable model has no place in iCloud backups
        var mutable = dir
        try? mutable.setResourceValues(values)
        return dir
    }

    /// True once a previous launch finished downloading.
    nonisolated static var isDownloaded: Bool { UserDefaults.standard.bool(forKey: "sayso.voice.downloaded") }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        if model != nil { return }
        // The Neural Engine is the fast path. If it can't build the model (the simulator, some devices), use the CPU and GPU.
        #if targetEnvironment(simulator)
        let preferred: [MLComputeUnits] = [.cpuOnly]
        #else
        let preferred: [MLComputeUnits] = [.all, .cpuAndGPU]
        #endif
        var lastError: Error?
        for units in preferred {
            do {
                model = try await KokoroTTSModel.fromPretrained(
                    modelId: Self.modelId, voice: Self.voice, cacheDir: Self.cacheDir, offlineMode: Self.isDownloaded,
                    computeUnits: units, progressHandler: { fraction, _ in progress(fraction) })
                lastError = nil
                break
            } catch { lastError = error }
        }
        if let lastError { throw lastError }
        UserDefaults.standard.set(true, forKey: "sayso.voice.downloaded")
    }

    func synthesize(_ text: String) throws -> [Float] {
        guard let model else { return [] }
        return try model.synthesize(text: text, voice: Self.voice, language: "en", speed: 1.0)
    }
}

/// Plays 24 kHz mono samples back to back.
@MainActor
final class VoicePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var pending = 0
    private var drained: CheckedContinuation<Void, Never>?
    private(set) var isPlaying = false

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func begin() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        if !engine.isRunning { try? engine.start() }
        isPlaying = true
    }

    func enqueue(_ samples: [Float]) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        pending += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pending -= 1
                if self.pending <= 0 { self.drained?.resume(); self.drained = nil }
            }
        }
        if !node.isPlaying { node.play() }
    }

    /// Returns once everything queued has finished playing.
    func drain() async {
        guard pending > 0 else { isPlaying = false; return }
        await withCheckedContinuation { drained = $0 }
        isPlaying = false
    }

    func stop() {
        node.stop()
        pending = 0
        drained?.resume()
        drained = nil
        isPlaying = false
    }
}

/// What reads well: no bullets, emoji or symbols, and times and punctuation that sound natural.
enum SpeechText {
    static func clean(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "•", with: "")
        s = s.replacingOccurrences(of: "✓", with: "")
        s = s.replacingOccurrences(of: "→", with: " to ")
        s = s.replacingOccurrences(of: "·", with: ",")
        s = s.replacingOccurrences(of: "…", with: ".")
        s = s.replacingOccurrences(of: #"[\p{Extended_Pictographic}]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bAM\b"#, with: "A M", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bPM\b"#, with: "P M", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\n+\s*"#, with: ". ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\.\s*\."#, with: ".", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
extension NeuralVoice {
    /// Simulator check: download, synthesize one sentence, report length and loudness.
    static func debugSelfTest() async {
        let started = Date.now
        var report = ""
        do {
            let engine = VoiceEngine()
            try await engine.load { _ in }
            let loaded = Date.now.timeIntervalSince(started)
            let t0 = Date.now
            let samples = try await engine.synthesize("Hello! I added dinner with Ankit to your calendar for Saturday at 8 P M.")
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            report = String(format: "OK samples=%d seconds=%.2f rms=%.4f load=%.1fs synth=%.2fs", samples.count, Double(samples.count) / 24000, rms, loaded, Date.now.timeIntervalSince(t0))
            // Save a WAV so it can be listened to.
            let wav = URL.documentsDirectory.appending(path: "voice-test.wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
            if let file = try? AVAudioFile(forWriting: wav, settings: format.settings),
               let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) {
                buf.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
                try? file.write(from: buf)
            }
        } catch {
            report = "FAIL \(error)"
        }
        try? report.write(to: URL.documentsDirectory.appending(path: "voice-test.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
