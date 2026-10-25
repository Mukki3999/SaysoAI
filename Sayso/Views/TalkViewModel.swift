import SwiftUI
import MessageUI
import Observation
import PhotosUI
import UIKit

enum TalkState: Equatable {
    case idle, listening, thinking
}

struct PendingPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage?

    init(data: Data) {
        self.data = data
        self.image = UIImage(data: data)
    }
}

struct MenuSeed {
    let data: Data
    let text: String
}

@MainActor @Observable
final class TalkViewModel {
    let speech = SpeechService()
    let agent = AgentService()
    let life: LifeStore
    let day: DayStore
    private let speaker = Speaker()

    init() {
        let life = LifeStore()
        self.life = life
        day = DayStore(life: life)
    }

    enum PlannerStep { case mustDos, focus, behind }

    // MARK: Conversation

    private(set) var messages: [ChatMessage] = []
    private(set) var state: TalkState = .idle
    private(set) var thinkingStatus = "Thinking…"
    /// What is typed in the composer.
    var input = ""
    /// A photo waiting in the composer for the user to say what to do with it.
    var attachment: PendingPhoto?
    private var lastUserText = ""
    private var requestID = 0

    var speakReplies = UserDefaults.standard.bool(forKey: "sayso.speakReplies") {
        didSet {
            UserDefaults.standard.set(speakReplies, forKey: "sayso.speakReplies")
            if !speakReplies { speaker.stop() }
        }
    }

    // Planner and menu
    let planner = PlannerSettings()
    var planSession: DayPlanSession?
    var showManualPlan = false
    var showMenu = false
    var menuSeed: MenuSeed?
    private(set) var plannerStep: PlannerStep?
    private var draftTasks: [PlanTask] = []

    /// The proposal being looked at in the full review sheet.
    var reviewing: ActionPlan?
    private let executor = ActionExecutor()
    private var pressing = false
    private var startTask: Task<Void, Never>?

    var canSend: Bool { state == .idle }

    var waveMode: WaveView.Mode {
        switch state {
        case .listening: .listening
        case .thinking: .thinking
        case .idle: .idle
        }
    }

    // MARK: Messages

    private func append(_ message: ChatMessage) { messages.append(message) }

    /// An assistant reply. Read aloud if the user asked for that.
    func say(_ text: String, choices: [Choice] = []) {
        clearChoices()
        append(ChatMessage(role: .assistant, content: .text(text), choices: choices))
        state = .idle
        if speakReplies { speaker.speak(text) }
    }

    private func fail(_ error: Error) {
        let needsSettings = error is PermissionDenied || speech.permissionDenied
        clearChoices()
        append(ChatMessage(role: .assistant, content: .error(Self.message(for: error), needsSettings: needsSettings)))
        state = .idle
    }

    private func fail(message: String) {
        clearChoices()
        append(ChatMessage(role: .assistant, content: .error(message, needsSettings: false)))
        state = .idle
    }

    private func clearChoices() {
        for i in messages.indices where !messages[i].choices.isEmpty { messages[i].choices = [] }
    }

    private static func message(for error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        // Always say what failed, so a report can be acted on.
        return "Something went wrong. Try again.\n\(Diagnostics.describe(error))"
    }

    /// Starts over with an empty thread and the home screen.
    func newChat() {
        requestID += 1
        speaker.stop()
        agent.resetConversation()
        plannerStep = nil
        draftTasks = []
        attachment = nil
        input = ""
        messages = []
        if state != .idle { Task { await speech.cancel() } }
        state = .idle
        Task { await refreshDay() }
    }

    /// Stops waiting on the model.
    func cancelThinking() {
        requestID += 1
        agent.resetConversation()
        plannerStep = nil
        state = .idle
    }

    func retry() {
        guard canSend, !lastUserText.isEmpty else { return }
        if case .error = messages.last?.content { messages.removeLast() }
        Task { await process(lastUserText) }
    }

    // MARK: Sending

    /// The composer's Send button: text, or a photo with optional text.
    func submitComposer() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let photo = attachment {
            attachment = nil
            input = ""
            Task { await sendPhoto(photo, text: text) }
        } else if !text.isEmpty {
            input = ""
            Task { await send(text) }
        }
    }

    func send(_ text: String) async {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, canSend else { return }
        speaker.stop()
        clearChoices()
        append(ChatMessage(role: .user, content: .text(said)))
        await process(said)
    }

    /// Tappable suggestion: same path as typing.
    func ask(_ text: String) async { await send(text) }

    private func process(_ text: String) async {
        lastUserText = text
        if let step = plannerStep { await handlePlannerAnswer(step, text); return }
        state = .thinking
        thinkingStatus = "Thinking…"
        requestID += 1
        let id = requestID
        let agent = self.agent
        let context = conversationContext()
        let hasPending = hasPendingProposal
        do {
            let outcome = try await withTimeout(seconds: 60) {
                try await agent.respond(to: text, forceMain: hasPending, context: context)
            }
            guard id == requestID, state == .thinking else { return }   // cancelled or replaced meanwhile
            await apply(outcome)
        } catch {
            guard id == requestID else { return }
            agent.resetConversation()
            fail(error)
        }
    }

    private func apply(_ outcome: AgentOutcome) async {
        switch outcome {
        case .question(let q): say(q)
        case .answer(let a): say(a)
        case .plan(let plan): propose(plan)
        case .planner(let intent): await begin(intent)
        }
    }

    /// Puts a proposal in the thread. A newer proposal replaces one that was never approved.
    func propose(_ plan: ActionPlan) {
        clearChoices()
        for m in messages { if case .proposal(let old) = m.content, old.status == .pending { old.status = .replaced } }
        let n = plan.actions.count
        let lead = n == 1 ? "Got it. Approve it when it looks right." : "Here's what I'll set up. Approve when it looks right."
        append(ChatMessage(role: .assistant, content: .proposal(plan)))
        state = .idle
        if speakReplies { speaker.speak(lead) }
    }

    /// For the simulator's demo hooks.
    func show(_ plan: ActionPlan) {
        append(ChatMessage(role: .user, content: .text(plan.transcript)))
        propose(plan)
    }

    private var hasPendingProposal: Bool {
        messages.contains { if case .proposal(let p) = $0.content { p.status == .pending } else { false } }
    }

    /// A short summary of the last few turns, so "make it 6" or "and remind me" has something to refer to.
    private func conversationContext() -> String? {
        var lines: [String] = []
        // The newest user message is the request itself, so it is left out.
        for m in messages.dropLast().suffix(6) {
            switch (m.role, m.content) {
            case (.user, .text(let t)): lines.append("User: \(t.prefix(120))")
            case (.user, .photo(_, let c)): lines.append("User shared a photo. \(c.prefix(80))")
            case (.assistant, .text(let t)): lines.append("Sayso: \(t.prefix(140))")
            case (.assistant, .proposal(let p)):
                let items = p.actions.map { $0.card }.joined(separator: "; ")
                switch p.status {
                case .pending: lines.append("Sayso proposed, not yet approved: \(items.prefix(260))")
                case .done: lines.append("Sayso did: \(items.prefix(260))")
                case .cancelled, .replaced: break
                }
            case (.assistant, .planCard): lines.append("Sayso made a plan for the day.")
            default: break
            }
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : String(text.suffix(700))
    }

    // MARK: Voice

    /// Tap the mic once for hands-free: Sayso stops itself after you pause. Or hold and release.
    private(set) var handsFree = false
    private var pressStart = Date.now
    private var monitorTask: Task<Void, Never>?

    func pressBegan() {
        // A tap while hands-free listening means "I'm done".
        if state == .listening, handsFree {
            Task { await finishListening() }
            return
        }
        guard !pressing, canSend else { return }
        pressing = true
        handsFree = false
        pressStart = .now
        speaker.stop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        startTask = Task {
            do {
                try await speech.start()
                state = .listening
                startMonitor()
            } catch {
                pressing = false
                handsFree = false
                fail(error)
            }
        }
    }

    func pressEnded() {
        guard pressing else { return }
        pressing = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // A quick tap switches to hands-free; a longer hold ends on release.
        if Date.now.timeIntervalSince(pressStart) < 0.4 {
            handsFree = true
            return
        }
        Task {
            await startTask?.value
            if state == .listening { await finishListening() }
        }
    }

    /// Hands-free end-of-speech detection: stops after a pause once words were heard.
    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            let began = Date.now
            var lastVoice = Date.now
            var lastText = ""
            var heardWords = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.state == .listening else { return }
                let text = self.speech.transcript
                if text != lastText || self.speech.level > 0.15 { lastVoice = .now; lastText = text }
                if !text.isEmpty { heardWords = true }
                let silence = Date.now.timeIntervalSince(lastVoice)
                let total = Date.now.timeIntervalSince(began)
                if (self.handsFree && heardWords && silence > 1.4)
                    || (self.handsFree && !heardWords && total > 8)
                    || total > 45 {
                    await self.finishListening()
                    return
                }
            }
        }
    }

    private func finishListening() async {
        guard state == .listening else { return }
        monitorTask?.cancel()
        handsFree = false
        state = .thinking
        thinkingStatus = "Listening…"
        let text = await speech.stop()
        state = .idle
        guard text.count > 1 else {
            fail(message: "I didn't catch that. Tap the mic and try again, or type it.")
            return
        }
        await send(text)
    }

    // MARK: Photos

    func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            fail(message: "Sayso couldn't open that photo.")
            return
        }
        receivePhoto(data)
    }

    /// The photo waits in the composer so the user can say what they want.
    func receivePhoto(_ data: Data) {
        attachment = PendingPhoto(data: data)
    }

    /// Menus go to the Menu Helper. Anything else is read on the iPhone and turned into actions.
    func sendPhoto(_ photo: PendingPhoto, text said: String) async {
        guard canSend else { return }
        clearChoices()
        if let image = photo.image { append(ChatMessage(role: .user, content: .photo(image, caption: said))) }
        lastUserText = said
        state = .thinking
        thinkingStatus = "Reading your photo…"
        requestID += 1
        let id = requestID
        do {
            let scan = try await withTimeout(seconds: 30) { try await MenuOCRService.read(photo.data) }
            guard id == requestID, state == .thinking else { return }
            if MenuDetector.looksLikeMenu(scan.lines, userText: said) || said == "What should I eat?" {
                menuSeed = MenuSeed(data: photo.data, text: said == "What should I eat?" ? "" : said)
                showMenu = true
                say("That looks like a menu. I've opened it so you can tell me what you're in the mood for.")
                return
            }
            let text = String(scan.lines.map(\.text).joined(separator: "\n").prefix(1800))
            let firstLine = scan.lines.first?.text ?? "your photo"
            let ask = said.isEmpty
                ? "Create the calendar events, reminders and alarms it implies. For example, for a booking add the event and a reminder to leave beforehand."
                : "The user says: \(said)"
            let prompt = "The user shared a photo. This is the text on it:\n\"\"\"\n\(text)\n\"\"\"\n\(ask)"
            let agent = self.agent
            let label = "Photo: \(firstLine.prefix(60))"
            thinkingStatus = "Thinking…"
            let outcome = try await withTimeout(seconds: 60) { try await agent.respond(to: prompt, shownAs: label) }
            guard id == requestID, state == .thinking else { return }
            await apply(outcome)
        } catch {
            guard id == requestID else { return }
            fail(error)
        }
    }

    // MARK: Proposals

    func approve(_ plan: ActionPlan) async {
        guard plan.status == .pending, !plan.isExecuting else { return }
        plan.isExecuting = true
        let ran = await executor.run(plan.approve())
        plan.results = ran
        plan.status = .done
        plan.isExecuting = false
        life.add(ran.filter { if case .failed = $0.outcome { false } else { true } }.map(\.action))
        if ran.count == 1, case .ready(let deferred) = ran[0].outcome {
            performDeferred(deferred, resultID: ran[0].id, in: plan)
        }
        agent.resetConversation()
        Task { await refreshDay() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func cancel(_ plan: ActionPlan) {
        guard plan.status == .pending else { return }
        plan.status = .cancelled
        reviewing = nil
        agent.resetConversation()
    }

    func undo(_ id: ActionResult.ID, in plan: ActionPlan) async {
        guard let i = plan.results?.firstIndex(where: { $0.id == id }),
              case .completed(let undo?) = plan.results?[i].outcome else { return }
        do {
            let actionID = plan.results?[i].action.id
            try await undo()
            if let actionID { life.remove(actionID) }
            plan.results?.remove(at: i)
            Task { await refreshDay() }
        } catch {
            plan.results?[i].outcome = .failed("Couldn't undo. Remove it in the \(plan.results?[i].symbol == "calendar" ? "Calendar" : "system") app.", needsSettings: false)
        }
    }

    /// Composer sheets are presented from the chat screen, so they never stack on the review sheet.
    var messageRequest: MessageComposeRequest?
    var emailRequest: EmailComposeRequest?
    var mailtoURL: URL?

    func performDeferred(_ deferred: DeferredAction, resultID: ActionResult.ID, in plan: ActionPlan) {
        Task {
            do {
                switch deferred {
                case .message(let d):
                    let request = try await MessageAction.prepare(d)
                    guard MFMessageComposeViewController.canSendText() else {
                        throw ToolError("This device can't send text messages.")
                    }
                    reviewing = nil
                    messageRequest = request
                case .email(let d):
                    let request = try await EmailAction.prepare(d)
                    reviewing = nil
                    if MFMailComposeViewController.canSendMail() {
                        emailRequest = request
                    } else {
                        // No Mail account set up: hand the draft to the default mail app. The user still taps Send.
                        var c = URLComponents()
                        c.scheme = "mailto"
                        c.path = request.recipients.joined(separator: ",")
                        c.queryItems = [URLQueryItem(name: "subject", value: request.subject),
                                        URLQueryItem(name: "body", value: request.body)]
                        mailtoURL = c.url
                    }
                case .directions(let d):
                    try await DirectionsAction.open(d)
                }
            } catch {
                guard let i = plan.results?.firstIndex(where: { $0.id == resultID }) else { return }
                plan.results?[i].outcome = .failed(error.localizedDescription, needsSettings: error is PermissionDenied)
            }
        }
    }

    func refreshDay() async { await day.refresh(agent: agent) }
    func connectDay() async { await day.connect(agent: agent) }

    // MARK: Plan my day and Rescue my day

    /// Button or voice. Without Apple Intelligence the manual form takes over.
    func startPlanning(mustDos: String? = nil) {
        guard canSend else { return }
        append(ChatMessage(role: .user, content: .text("Plan my day")))
        Task { await begin(.planDay(mustDos: mustDos)) }
    }

    func startRescue(minutes: Int) {
        guard canSend else { return }
        append(ChatMessage(role: .user, content: .text(minutes == 0 ? "Re-plan the rest of my day" : "I'm \(minutes) minutes behind")))
        Task { await begin(.rescueDay(minutesBehind: minutes)) }
    }

    func handle(_ route: IntentRouter.Route) {
        switch route {
        case .plan: startPlanning()
        case .rescue(let minutes): startRescue(minutes: minutes)
        }
    }

    func choose(_ choice: Choice) {
        switch choice.action {
        case .focus(let f):
            clearChoices()
            append(ChatMessage(role: .user, content: .text(choice.label)))
            Task { await handlePlannerAnswer(.focus, f.rawValue) }
        case .behind(let m):
            clearChoices()
            append(ChatMessage(role: .user, content: .text(choice.label)))
            Task { await handlePlannerAnswer(.behind, "\(m)") }
        case .send(let text):
            Task { await send(text) }
        }
    }

    func cancelPlanner() {
        plannerStep = nil
        draftTasks = []
        agent.resetConversation()
        say("No problem. I stopped planning.")
    }

    func closePlanSession() {
        if let session = planSession, session.committedCount > 0 {
            let n = session.committedCount
            say("Done. \(n) \(n == 1 ? "change" : "changes") in your “\(PlanningCalendar.calendarName)” calendar. You can undo or remove them any time.")
        }
        planSession = nil
        plannerStep = nil
        draftTasks = []
        Task { await refreshDay() }
    }

    /// The manual form's result: no language model involved.
    func submitManualPlan(tasks: [PlanTask], focus: FocusPreference) async {
        showManualPlan = false
        draftTasks = tasks
        await buildPlan(focus: focus)
    }

    private func begin(_ intent: PlannerIntent) async {
        switch intent {
        case .planDay(let mustDos):
            guard agent.isModelAvailable else { state = .idle; showManualPlan = true; return }
            if let mustDos {
                await handlePlannerAnswer(.mustDos, mustDos)
            } else {
                plannerStep = .mustDos
                say("What must get done today? Tell me in any order, with how long each takes and any deadlines.")
            }
        case .rescueDay(let minutes):
            if let minutes {
                await buildRescue(behind: minutes)
            } else {
                plannerStep = .behind
                say("How far behind are you?", choices: [15, 30, 45, 60, 90].map { Choice(label: "\($0) min", action: .behind($0)) })
            }
        }
    }

    private func handlePlannerAnswer(_ step: PlannerStep, _ text: String) async {
        let lowered = text.lowercased()
        if ["cancel", "never mind", "nevermind", "forget it", "stop"].contains(where: { lowered.hasPrefix($0) }) {
            cancelPlanner()
            return
        }
        switch step {
        case .mustDos:
            state = .thinking
            thinkingStatus = "Reading your list…"
            do {
                let tasks = try await agent.parseTasks(text)
                guard !tasks.isEmpty else {
                    plannerStep = .mustDos
                    say("I didn't catch any tasks. What must get done today?")
                    return
                }
                draftTasks = tasks
                plannerStep = .focus
                say("Got \(tasks.count) \(tasks.count == 1 ? "task" : "tasks"). When do you focus best?",
                    choices: FocusPreference.allCases.map { Choice(label: $0 == .none ? "No preference" : $0.label, action: .focus($0)) })
            } catch {
                // The model couldn't parse it: fall back to the form.
                plannerStep = nil
                state = .idle
                showManualPlan = true
            }
        case .focus:
            await buildPlan(focus: FocusPreference.parse(text))
        case .behind:
            guard let minutes = SpokenMinutes.parse(text) else {
                say("How many minutes behind are you?", choices: [15, 30, 45, 60, 90].map { Choice(label: "\($0) min", action: .behind($0)) })
                return
            }
            await buildRescue(behind: minutes)
        }
    }

    private func buildPlan(focus: FocusPreference) async {
        plannerStep = nil
        planner.focus = focus
        state = .thinking
        thinkingStatus = "Planning your day…"
        let session = DayPlanSession(mode: .plan, tasks: draftTasks, focus: focus, settings: planner.plan)
        await present(session)
    }

    private func buildRescue(behind: Int) async {
        plannerStep = nil
        state = .thinking
        thinkingStatus = "Re-planning the rest of today…"
        let session = DayPlanSession(mode: .rescue(behind: behind), tasks: [], focus: planner.focus, settings: planner.plan)
        await present(session)
    }

    private func present(_ session: DayPlanSession) async {
        do {
            try await session.prepare(agent: agent)
            clearChoices()
            append(ChatMessage(role: .assistant, content: .planCard(session)))
            planSession = session
            state = .idle
        } catch {
            fail(error)
        }
    }
}
