import AVFoundation
import UIKit

struct Choice: Identifiable {
    enum Action { case focus(FocusPreference), behind(Int), send(String) }
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

    let id = UUID()
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
