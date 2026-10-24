import FoundationModels
import Observation

enum AgentOutcome {
    case plan(ActionPlan)
    case question(String)   // the model needs one more detail
    case answer(String)     // a reply to a question about the user's day
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

    /// One friendly sentence about the user's day. Nil if the model isn't available or fails.
    func briefing(for agenda: String) async -> String? {
        guard isModelAvailable else { return nil }
        let session = LanguageModelSession(model: model, instructions: "You write a one-sentence briefing from the user's schedule. Max 22 words, warm and plain, no emojis, no lists. Mention the most important or next thing.")
        guard let reply = try? await session.respond(to: agenda, options: GenerationOptions(temperature: 0.3)) else { return nil }
        let text = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Drops conversation context. Call after a plan is approved or cancelled.
    func resetConversation() { session = nil }

    /// `shownAs` is what the confirmation sheet displays when the prompt isn't what the user literally said.
    func respond(to transcript: String, shownAs label: String? = nil) async throws -> AgentOutcome {
        await collector.reset()
        let session = self.session ?? makeSession()
        self.session = session
        do {
            let response = try await session.respond(to: transcript, options: GenerationOptions(temperature: 0.2))
            let actions = await collector.drain()
            if actions.isEmpty {
                // No actions queued: either a clarifying question or an answer about the user's day.
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix("?") { return .question(text) }
                self.session = nil
                return .answer(text)
            }
            self.session = nil
            return .plan(ActionPlan(actions: actions, transcript: label ?? transcript))
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
            OpenDirectionsTool(collector: collector),
            GetAgendaTool()
        ]
    }

    private func instructions() -> String {
        """
        You are Sayso, an assistant that turns spoken requests into device actions.
        Now: \(DateText.promptNow()).
        Upcoming days, use these exact dates:
        \(DateText.promptCalendar())

        Rules:
        - Always call tools. Never say you did something without calling one.
        - Split the request into every separate action and call a tool for each. Words like "and", "then", "also" usually mean another action.
        - Pick the tool by meaning: "wake me" or a clock time to ring = setAlarm; "timer" or "in 10 minutes" = startTimer; "remind me" = createReminder; plans, meetings, meals, appointments = createCalendarEvent; "text" or "message" = draftMessage; "email" = draftEmail; "directions" or "take me to" = openDirections.
        - Write dates and times as local yyyy-MM-dd'T'HH:mm:ss.
        - Bare hours with no AM or PM: alarms 4 to 11 are AM. Events and reminders 1 to 6 are PM, 7 to 11 are AM unless the request says tonight, dinner or evening. 12 is noon.
        - If the user gives no end time, leave end empty. Never invent locations, names or notes.
        - Questions about the user's schedule ("what's on tomorrow", "am I free Saturday"): call getAgenda for each day asked, then answer in one or two short sentences. Do not call action tools for questions.
        - Make sensible choices instead of asking. Ask one short clarifying question, with no tool calls, only when a required detail is truly missing, such as who to message or which day.
        - Write message and email text in the user's voice, short and natural.
        - After the tool calls, reply in one short sentence.

        Example: "Dinner with Ankit Saturday at 8 at Nobu, remind me to book a table, and wake me at 6:30"
        -> createCalendarEvent(Dinner with Ankit, Saturday 20:00, location Nobu); createReminder(Book a table); setAlarm(6:30).
        Example: "Text Sam I'm 10 minutes late and take me to Blue Bottle"
        -> draftMessage(Sam, "Running about 10 minutes late"); openDirections(Blue Bottle).
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
