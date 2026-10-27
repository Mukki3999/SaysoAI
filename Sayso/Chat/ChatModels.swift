import AVFoundation
import UIKit

struct Choice: Identifiable {
    enum Action { case focus(FocusPreference), behind(Int), send(String), proposeDelete(EventDeleteDraft) }
    let id = UUID()
    let label: String
    let action: Action
}

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    enum Content {
        case text(String)
        case photo(UIImage, caption: String)
        case proposal(ActionPlan)
        case planCard(DayPlanSession)
        case error(String, needsSettings: Bool)
    }

    var id = UUID()
    var date = Date.now
    let role: Role
    var content: Content
    /// Quick answers shown under the message until one is used.
    var choices: [Choice] = []
}

/// Reads assistant replies aloud when the user turns that on.
@MainActor
final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}


/// The one shared conversation, kept on the iPhone between launches.
/// Only what is worth coming back to is saved: words, and proposals that are waiting or were done.
enum ChatStore {
    struct Stored: Codable {
        enum Kind: String, Codable { case text, proposal }
        var id: UUID
        var date: Date
        var fromUser: Bool
        var kind: Kind
        var text: String
        var actions: [ProposedAction] = []
        var transcript = ""
    }

    private static var url: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Sayso", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "chat.json")
    }

    @MainActor
    static func save(_ messages: [ChatMessage]) {
        let stored: [Stored] = messages.suffix(150).compactMap { m in
            let user = m.role == .user
            switch m.content {
            case .text(let t):
                return Stored(id: m.id, date: m.date, fromUser: user, kind: .text, text: t)
            case .photo(_, let caption):
                return Stored(id: m.id, date: m.date, fromUser: true, kind: .text, text: caption.isEmpty ? "Photo" : "Photo: \(caption)")
            case .proposal(let plan):
                switch plan.status {
                case .pending:
                    return Stored(id: m.id, date: m.date, fromUser: false, kind: .proposal, text: "", actions: plan.actions, transcript: plan.transcript)
                case .done:
                    let lines = (plan.results?.map(\.action) ?? plan.actions).map(\.card).joined(separator: "\n")
                    return Stored(id: m.id, date: m.date, fromUser: false, kind: .text, text: "Done ✓\n" + lines)
                case .cancelled, .replaced:
                    return nil
                }
            case .planCard, .error:
                return nil
            }
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @MainActor
    static func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return stored.map { s in
            var m: ChatMessage
            switch s.kind {
            case .text: m = ChatMessage(role: s.fromUser ? .user : .assistant, content: .text(s.text))
            case .proposal: m = ChatMessage(role: .assistant, content: .proposal(ActionPlan(actions: s.actions, transcript: s.transcript)))
            }
            m.id = s.id
            m.date = s.date
            return m
        }
    }

    static func erase() { try? FileManager.default.removeItem(at: url) }
}
