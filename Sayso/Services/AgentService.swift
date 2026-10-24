import FoundationModels
import Observation

enum AgentOutcome {
    case plan(ActionPlan)
    case question(String)
}

@MainActor @Observable
final class AgentService {
    private let model = SystemLanguageModel.default
    private let collector = PlanCollector()
    private var session: LanguageModelSession?

    var isModelAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    var unavailableReason: String {
        guard case .unavailable(let reason) = model.availability else { return "" }
        switch reason {
        case .deviceNotEligible:
            return "Sayso uses Apple Intelligence, which this iPhone doesn't support. It needs an iPhone 15 Pro or newer."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings, then come back. Sayso uses it to understand what you say."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready on this iPhone. Try again in a few minutes."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    /// Drops conversation context. Call after a plan is approved or cancelled.
    func resetConversation() { session = nil }

    func respond(to transcript: String) async throws -> AgentOutcome {
        await collector.reset()
        let session = self.session ?? makeSession()
        self.session = session
        do {
            let response = try await session.respond(to: transcript)
            let actions = await collector.drain()
            if actions.isEmpty {
                // No tool calls: the model is asking a question (or couldn't help).
                return .question(response.content)
            }
            self.session = nil
            return .plan(ActionPlan(actions: actions, transcript: transcript))
        } catch let error as LanguageModelSession.ToolCallError {
            self.session = nil
            throw ToolError(error.underlyingError.localizedDescription)
        } catch let error as LanguageModelSession.GenerationError {
            self.session = nil
            throw ToolError(Self.message(for: error))
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, tools: tools, instructions: instructions())
    }

    private var tools: [any Tool] {
        [
            CreateCalendarEventTool(collector: collector),
            CreateReminderTool(collector: collector),
            SetAlarmTool(collector: collector),
            StartTimerTool(collector: collector),
            DraftMessageTool(collector: collector),
            DraftEmailTool(collector: collector),
            OpenDirectionsTool(collector: collector)
        ]
    }

    private func instructions() -> String {
        """
        You are Sayso, an assistant that turns spoken requests into device actions.
        Now: \(DateText.promptNow()). Resolve words like "tomorrow" and "Friday at noon" against this date and time zone.
        Rules:
        - Always use tools to act. Never say you did something without calling a tool.
        - One request can need several tool calls. Make all of them.
        - Write dates and times as local yyyy-MM-dd'T'HH:mm:ss.
        - If a required detail is missing or ambiguous, ask one short clarifying question instead of guessing, and call no tools.
        - Keep replies brief.
        """
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation: "Sayso can't help with that request."
        case .exceededContextWindowSize: "That was too long. Try a shorter request."
        case .unsupportedLanguageOrLocale: "Sayso doesn't support that language yet."
        default: "Sayso couldn't understand that. Try again."
        }
    }
}
