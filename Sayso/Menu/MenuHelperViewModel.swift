import SwiftUI
import UIKit

@MainActor @Observable
final class MenuHelperViewModel {
    enum Phase: Equatable {
        case empty
        case reading(String)
        case ready
        case thinking
        case error(String)
    }

    static let disclaimer = "Based on menu text, not allergy-safe. Check with the restaurant."

    /// With Apple Intelligence off, the menu is shown as a searchable list instead of picks.
    let modelAvailable: Bool
    let speech = SpeechService()

    private(set) var phase: Phase = .empty
    private(set) var image: UIImage?
    private(set) var lines: [OCRLine] = []
    private(set) var items: [MenuItem] = []
    private(set) var picks: [MenuPick] = []
    private(set) var outcome: MenuFilter.Outcome?
    private(set) var selectedID: UUID?
    private(set) var isListening = false
    private(set) var micError: String?
    var prefs = MenuPreferences()
    var input = ""
    var search = ""

    private var monitor: Task<Void, Never>?

    init(modelAvailable: Bool) {
        #if DEBUG
        let demo = ProcessInfo.processInfo.environment["SAYSO_DEMO_MENU"]
        self.modelAvailable = demo == "list" ? false : (modelAvailable || demo == "picks")
        #else
        self.modelAvailable = modelAvailable
        #endif
    }

    var highlighted: Set<Int> {
        guard let id = selectedID, let item = items.first(where: { $0.id == id }) else { return [] }
        return Set(item.lineIndexes)
    }

    // MARK: Photo -> dishes

    func load(_ data: Data) async {
        phase = .reading("Reading the menu…")
        picks = []
        outcome = nil
        selectedID = nil
        do {
            let scan = try await MenuOCRService.read(data)
            image = UIImage(data: scan.imageData)
            lines = scan.lines
            phase = .reading("Finding the dishes…")
            items = await parse(scan.lines)
            guard !items.isEmpty else {
                phase = .error("Sayso couldn't find any dishes. Try a straighter photo with better light, close enough to read.")
                return
            }
            phase = .ready
            if modelAvailable { if !prefs.isDefault { await recompute() } } else { refreshList() }
        } catch {
            phase = .error((error as? LocalizedError)?.errorDescription ?? "Sayso couldn't read that photo.")
        }
    }

    /// The model reads the menu in chunks; the plain-Swift parser backs it up when it fails or finds little.
    private func parse(_ lines: [OCRLine]) async -> [MenuItem] {
        let plain = MenuHeuristicParser.parse(lines)
        guard modelAvailable, let smart = try? await MenuParser.parse(lines) else { return plain }
        return smart.count >= max(3, plain.count / 2) ? smart : plain
    }

    // MARK: Preferences -> picks

    func submit(_ text: String? = nil) async {
        let said = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !items.isEmpty else { return }
        input = ""
        phase = .thinking
        prefs = await PreferenceParser.update(prefs, with: said)
        await recompute()
    }

    func remove(_ chip: MenuPreferences.Chip) async {
        prefs.remove(chip)
        await recompute()
    }

    /// Filter in plain Swift, then (with Apple Intelligence) let the model choose three of what is left.
    func recompute() async {
        selectedID = nil
        let result = MenuFilter.apply(items, prefs)
        outcome = result
        guard modelAvailable else { picks = []; phase = .ready; return }
        phase = .thinking
        if result.candidates.isEmpty {
            picks = []
        } else if let ranked = try? await MenuRanker.rank(result.candidates, prefs) {
            picks = ranked
        } else {
            picks = result.candidates.prefix(3).map { MenuPick(item: $0, reason: MenuFilter.reasonFacts($0, prefs)) }
        }
        phase = .ready
    }

    /// Without the model there is nothing to wait for.
    func refreshList() { outcome = MenuFilter.apply(items, prefs, limit: 500) }

    /// The list shown when Apple Intelligence is off: filtered by the chips and the search box.
    var listItems: [MenuItem] {
        let base = MenuFilter.apply(items, prefs, limit: 500).candidates.sorted { $0.lineIndexes.first ?? 0 < $1.lineIndexes.first ?? 0 }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? base : base.filter { $0.searchText.lowercased().contains(q) }
    }

    func select(_ item: MenuItem) { withAnimation(.smooth) { selectedID = selectedID == item.id ? nil : item.id } }

    // MARK: Voice (the same speech service as the main screen)

    func toggleMic() async {
        if isListening { await finishListening(); return }
        micError = nil
        do {
            try await speech.start()
            isListening = true
            startMonitor()
        } catch {
            micError = (error as? LocalizedError)?.errorDescription ?? "Couldn't use the microphone."
        }
    }

    private func startMonitor() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            let began = Date.now
            var lastChange = Date.now
            var lastText = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.isListening else { return }
                let text = self.speech.transcript
                if text != lastText || self.speech.level > 0.15 { lastChange = .now; lastText = text }
                if (!text.isEmpty && Date.now.timeIntervalSince(lastChange) > 1.4) || Date.now.timeIntervalSince(began) > 30 {
                    await self.finishListening()
                    return
                }
            }
        }
    }

    private func finishListening() async {
        guard isListening else { return }
        monitor?.cancel()
        isListening = false
        let text = await speech.stop()
        if text.count > 1 { await submit(text) }
    }
}
