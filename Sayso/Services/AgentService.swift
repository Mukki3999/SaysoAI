import FoundationModels
import Observation

enum AgentOutcome: Sendable {
    case plan(ActionPlan)
    case question(String)   // the model needs one more detail
    case answer(String)     // a reply to a question about the user's day
    case planner(PlannerIntent)   // start Plan my day or Rescue my day
}

@MainActor @Observable
final class AgentService {
    private let model = SystemLanguageModel.default
    private let collector = PlanCollector()
    private let directory = EventDirectory()
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
    func respond(to transcript: String, shownAs label: String? = nil, forceMain: Bool = false, compact: Bool = false) async throws -> AgentOutcome {
        // "Plan my day" and "I'm behind" start their own flows. Catching them here keeps their tools out of the model's small window.
        if session == nil, label == nil, let intent = PlannerRouter.route(transcript) { return .planner(intent) }
        await collector.reset()
        if self.session == nil { await directory.reset() }
        // Edits get their own small tool set: the on-device model's context window is small.
        let editing = self.session == nil && !forceMain && Self.looksLikeEdit(transcript)
        let session = self.session ?? (editing ? makeEditSession() : makeSession(compact: compact))
        self.session = session
        do {
            let response = try await session.respond(to: transcript, options: GenerationOptions(temperature: 0.2))
            let actions = await collector.drain()
            if actions.isEmpty {
                if editing, response.content.contains("NOT_EDIT") {
                    self.session = nil
                    return try await respond(to: transcript, shownAs: label, forceMain: true)
                }
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
            if error.underlyingError is PermissionDenied { throw error.underlyingError }
            throw ToolError(error.underlyingError.localizedDescription)
        } catch let error as LanguageModelSession.GenerationError {
            self.session = nil
            // Too much for the small window: try once more with shorter instructions.
            if case .exceededContextWindowSize = error, !compact {
                return try await respond(to: transcript, shownAs: label, forceMain: true, compact: true)
            }
            throw ToolError(Self.message(for: error))
        }
    }

    private func makeSession(compact: Bool = false) -> LanguageModelSession {
        LanguageModelSession(model: model, tools: tools, instructions: instructions(compact: compact))
    }

    /// For the self-test: how big the model's fixed input is.
    var sizeSummary: String {
        "\(tools.count) tools, instructions \(instructions().count) characters (compact: \(instructions(compact: true).count))"
    }

    // MARK: Planner helpers (the model parses and words things; the Scheduler does all the scheduling)

    @Generable
    enum ParsedPriority { case low, medium, high }

    @Generable
    struct ParsedTask {
        @Guide(description: "Short task name, like 'Finish report'")
        var title: String
        @Guide(description: "Minutes it takes. Use what the user said, otherwise a sensible estimate: quick call or email 15, errand 30, focused work 60")
        var minutes: Int
        @Guide(description: "high if the user calls it urgent, important or a must, low if optional, otherwise medium")
        var priority: ParsedPriority
        @Guide(description: "Deadline today in local yyyy-MM-dd'T'HH:mm:ss, only if the user gave a time it is due by")
        var deadline: String?
        @Guide(description: "True for work that needs concentration: writing, coding, studying, designing, planning")
        var deep: Bool
    }

    @Generable
    struct ParsedTasks {
        var tasks: [ParsedTask]
    }

    @Generable
    struct ReasonLines {
        @Guide(description: "One short line per block, in the same order")
        var lines: [String]
    }

    /// Turns "finish the deck by 3, gym, call mom for 10 minutes" into tasks. Never schedules anything.
    func parseTasks(_ text: String) async throws -> [PlanTask] {
        let session = LanguageModelSession(model: model, instructions: """
            You turn a spoken to-do list into tasks. Now: \(DateText.promptNow()). Do not schedule anything or pick times to do the tasks. \
            One task per item. Keep the user's wording short. Do not invent tasks.
            """)
        do {
            let parsed = try await session.respond(to: text, generating: ParsedTasks.self, options: GenerationOptions(temperature: 0.1)).content
            return parsed.tasks.compactMap { t in
                let title = t.title.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                let priority: TaskPriority = switch t.priority { case .low: .low; case .medium: .medium; case .high: .high }
                return PlanTask(title: title, minutes: min(max(t.minutes, 5), 480), priority: priority,
                                deadline: t.deadline.flatMap(DateText.parse), deep: t.deep)
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw ToolError(Self.message(for: error))
        }
    }

    /// Rewords the Scheduler's facts into short lines. Returns nil (keep the originals) unless every line comes back sane.
    func rewordReasons(_ facts: [String]) async -> [String]? {
        guard isModelAvailable, !facts.isEmpty, facts.count <= 12 else { return nil }
        let session = LanguageModelSession(model: model, instructions: "For each numbered scheduling fact, write one plain line of at most 12 words saying why the task sits there. Use only the facts given. No times, no emojis.")
        let prompt = facts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        guard let lines = try? await session.respond(to: prompt, generating: ReasonLines.self, options: GenerationOptions(temperature: 0.2)).content.lines,
              lines.count == facts.count,
              lines.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 100 }) else { return nil }
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func makeEditSession() -> LanguageModelSession {
        LanguageModelSession(
            model: model,
            tools: [FindEventsTool(directory: directory),
                    UpdateEventTool(collector: collector, directory: directory),
                    DeleteEventTool(collector: collector, directory: directory)],
            instructions: editInstructions())
    }

    /// Cheap check for "this sounds like changing an existing event". If it's wrong the edit session says NOT_EDIT and we retry.
    private static func looksLikeEdit(_ text: String) -> Bool {
        text.range(of: #"\b(cancel|delete|remove|reschedule|postpone|push|move|rename|shift|change|edit|update|clear)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
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

    private func instructions(compact: Bool = false) -> String {
        let examples = compact ? "" : """

        Example: "Dinner with Ankit Saturday at 8 at Nobu, remind me to book a table, and wake me at 6:30"
        -> createCalendarEvent(Dinner with Ankit, Saturday 20:00, location Nobu); createReminder(Book a table); setAlarm(6:30).
        Example: "Text Sam I'm 10 minutes late and take me to Blue Bottle"
        -> draftMessage(Sam, "Running about 10 minutes late"); openDirections(Blue Bottle).
        """
        return """
        You are Sayso, an assistant that turns spoken requests into device actions.
        Now: \(DateText.promptNow()).
        Upcoming days, use these exact dates:
        \(DateText.promptCalendar(days: compact ? 4 : 8))

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
        \(examples)
        """
    }

    private func editInstructions() -> String {
        """
        You are Sayso. You change or cancel events that are already on the user's calendar.
        Now: \(DateText.promptNow()).
        Upcoming days, use these exact dates:
        \(DateText.promptCalendar())

        Rules:
        - First call findEvents for the day or range the user means. A whole day runs 00:00:00 to 23:59:00. Put any words from the event's name in text.
        - Then call updateEvent or deleteEvent with the handle findEvents gave. Never invent a handle.
        - If findEvents lists several events and the user meant one, ask which one in one short sentence. Make no other calls.
        - "Cancel everything after 5" or "clear my afternoon": findEvents with all true for that range, then deleteEvent for every handle.
        - Moving an event to a new time: set newStart only. Renaming: set newTitle only.
        - Write times as local yyyy-MM-dd'T'HH:mm:ss. Bare hours: 1 to 6 are PM, 7 to 11 are AM unless the user says otherwise.
        - If the request is not about changing or cancelling an existing calendar event, reply exactly NOT_EDIT and call nothing.
        - After the tool calls, reply in one short sentence.
        """
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation: "Sayso can't help with that request."
        case .exceededContextWindowSize: "That was too long. Try a shorter request."
        case .unsupportedLanguageOrLocale: "Sayso doesn't support that language yet."
        default: "Sayso couldn't understand that (\(String(describing: error).prefix(40))). Try again."
        }
    }
}
