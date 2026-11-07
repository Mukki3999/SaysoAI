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
        messages = ChatStore.load()
    }

    /// Today is your schedule; Chat is the one conversation that never goes away.
    enum Tab: Hashable { case today, chat }
    var tab: Tab = .today

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
    private var planDay = Date.now

    /// The proposal being looked at in the full review sheet.
    var reviewing: ActionPlan?
    private let executor = ActionExecutor()
    private var pressing = false
    private var startTask: Task<Void, Never>?
    /// True while the microphone is still spinning up. A tap during that window must not start a second session.
    private var starting = false
    private var cancelStart = false

    var canSend: Bool { state == .idle }

    var waveMode: WaveView.Mode {
        switch state {
        case .listening: .listening
        case .thinking: .thinking
        case .idle: .idle
        }
    }

    // MARK: Messages

    private func append(_ message: ChatMessage) {
        messages.append(message)
        persist()
    }

    /// Saves the thread. Called whenever something in it changes, including a proposal's status.
    func persist() { ChatStore.save(messages) }

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

    private static func status(for text: String) -> String {
        let t = text.lowercased()
        if t.range(of: #"\b(calendar|schedule|meeting|event|tomorrow|today|free|busy)\b"#, options: .regularExpression) != nil { return "Checking your calendar…" }
        if t.range(of: #"\b(text|message|email)\b"#, options: .regularExpression) != nil { return "Drafting that…" }
        return "Thinking…"
    }

    /// Quick, model-side failures are worth one more try. Permission and timeout problems are not.
    private static func isRetryable(_ error: Error) -> Bool {
        if error is PermissionDenied { return false }
        let text = String(describing: error).lowercased()
        return !text.contains("too long") && !text.contains("can't help") && !text.contains("unsupported")
    }

    private static func message(for error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription,
           !d.lowercased().contains("deserialize"), !d.lowercased().contains("generat") { return d }
        // A friendly line first. The technical detail sits after the line break and is tucked behind "Details".
        return "I couldn't work that out. Rephrase it, or try again.\n\(Diagnostics.describe(error))"
    }

    /// Wipes the shared conversation. The only way it goes away.
    func newChat() {
        requestID += 1
        speaker.stop()
        agent.resetConversation()
        plannerStep = nil
        draftTasks = []
        attachment = nil
        input = ""
        messages = []
        ChatStore.erase()
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

    /// Puts the last request back in the composer so it can be reworded.
    func editLast() {
        if case .error = messages.last?.content { messages.removeLast(); persist() }
        input = lastUserText
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
        tab = .chat
        append(ChatMessage(role: .user, content: .text(said)))
        await process(said)
    }

    /// Tappable suggestion: same path as typing.
    func ask(_ text: String) async { await send(text) }

    private func process(_ text: String) async {
        lastUserText = text
        if let step = plannerStep { await handlePlannerAnswer(step, text); return }
        // "Cancel the dinner" while the dinner is still only a proposal means: drop the proposal.
        if let pending = pendingProposal, let cmd = EventCommand.parse(text), !cmd.words.isEmpty,
           pending.actions.contains(where: { a in cmd.words.allSatisfy { a.summary.lowercased().contains($0) } }) {
            cancel(pending)
            say("Okay, cancelled that.")
            return
        }
        state = .thinking
        thinkingStatus = Self.status(for: text)
        planDay = text.lowercased().contains("tomorrow") ? Calendar.current.date(byAdding: .day, value: 1, to: .now)! : .now
        requestID += 1
        let id = requestID
        let agent = self.agent
        let context = conversationContext()
        let hasPending = hasPendingProposal
        let started = Date.now
        func ask() async throws -> AgentOutcome {
            try await withTimeout(seconds: 60) {
                try await agent.respond(to: text, forceMain: hasPending, context: context, routeDeletes: true)
            }
        }
        do {
            let outcome: AgentOutcome
            do {
                outcome = try await ask()
            } catch where Self.isRetryable(error) && Date.now.timeIntervalSince(started) < 40 {
                // The small model sometimes stumbles on a perfectly good request. One quiet retry fixes most of those.
                guard id == requestID else { return }
                agent.resetConversation()
                outcome = try await ask()
            }
            guard id == requestID, state == .thinking else { return }   // cancelled or replaced meanwhile
            await apply(outcome)
            agent.prewarm()
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
        case .agenda(let day, let items):
            clearChoices()
            append(ChatMessage(role: .assistant, content: .agenda(day, items)))
            state = .idle
            if speakReplies { speaker.speak("\(day) you have \(items.count) \(items.count == 1 ? "thing" : "things").") }
        case .pickEvent(let q, let options):
            say(q, choices: options.map { Choice(label: ProposedAction(payload: $0).summary, action: .propose($0)) })
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
        tab = .chat
        append(ChatMessage(role: .user, content: .text(plan.transcript)))
        propose(plan)
    }

    private var pendingProposal: ActionPlan? {
        for m in messages.reversed() { if case .proposal(let p) = m.content, p.status == .pending { return p } }
        return nil
    }

    var hasPendingProposal: Bool {
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

    /// A touch sends many "changed" events. Only the first one counts, so the tail of a tap can't start a new recording.
    private var touchDown = false

    func pressBegan() {
        if touchDown { return }
        touchDown = true
        // A tap while hands-free listening means "I'm done".
        if state == .listening, handsFree {
            Task { await finishListening() }
            return
        }
        // Tapped again while the mic is still starting: that means "never mind". Don't open a second session.
        if starting { cancelStart = true; return }
        guard !pressing, canSend else { return }
        tab = .chat
        pressing = true
        handsFree = false
        pressStart = .now
        speaker.stop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        starting = true
        cancelStart = false
        startTask = Task {
            do {
                try await speech.start()
                starting = false
                // Only go to "listening" if nothing else took over while the mic started.
                guard state == .idle, !cancelStart else {
                    await speech.cancel()
                    handsFree = false
                    return
                }
                state = .listening
                startMonitor()
            } catch {
                starting = false
                pressing = false
                handsFree = false
                fail(error)
            }
        }
    }

    func pressEnded() {
        touchDown = false
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
        speech.clearTranscript()
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
        tab = .chat
        attachment = PendingPhoto(data: data)
    }

    /// Menus go to the Menu Helper. Anything else is read on the iPhone and turned into actions.
    func sendPhoto(_ photo: PendingPhoto, text said: String) async {
        guard canSend else { return }
        clearChoices()
        tab = .chat
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
        persist()
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
        persist()
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
                    guard MFMessageComposeViewController.canSendText() else {
                        throw ToolError("This device can't send text messages.")
                    }
                    switch try await ContactsResolver.lookup(d.recipient) {
                    case .one(let c): complete(ContactChoice(spoken: d.recipient, candidates: [], deferred: deferred), with: c)
                    case .many(let cs): reviewing = nil; contactChoice = ContactChoice(spoken: d.recipient, candidates: cs, deferred: deferred)
                    case .none: reviewing = nil; contactChoice = ContactChoice(spoken: d.recipient, candidates: [], deferred: deferred)
                    }
                case .email(let d):
                    switch try await ContactsResolver.lookup(d.recipient) {
                    case .one(let c): complete(ContactChoice(spoken: d.recipient, candidates: [], deferred: deferred), with: c)
                    case .many(let cs): reviewing = nil; contactChoice = ContactChoice(spoken: d.recipient, candidates: cs, deferred: deferred)
                    case .none: reviewing = nil; contactChoice = ContactChoice(spoken: d.recipient, candidates: [], deferred: deferred)
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

    /// Asked when a name matches several people, sounds close to someone, or matches nobody.
    struct ContactChoice: Identifiable {
        let id = UUID()
        let spoken: String
        let candidates: [ResolvedContact]
        let deferred: DeferredAction

        var isEmail: Bool { if case .email = deferred { true } else { false } }
        func label(_ c: ResolvedContact) -> String {
            let detail = isEmail ? c.email : c.phone
            return detail.map { "\(c.name) · \($0)" } ?? c.name
        }
    }
    var contactChoice: ContactChoice?
    var pickingContact: ContactChoice?

    /// A contact is settled: open the Messages or Mail composer with the draft. The user still taps Send.
    func complete(_ choice: ContactChoice, with c: ResolvedContact) {
        contactChoice = nil
        pickingContact = nil
        switch choice.deferred {
        case .message(let d):
            guard let phone = c.phone else { homeError = "\(c.name) has no phone number."; return }
            reviewing = nil
            messageRequest = MessageComposeRequest(recipients: [phone], body: d.body)
        case .email(let d):
            guard let email = c.email else { homeError = "\(c.name) has no email address."; return }
            reviewing = nil
            let request = EmailComposeRequest(recipients: [email], subject: d.subject, body: d.body)
            if MFMailComposeViewController.canSendMail() {
                emailRequest = request
            } else {
                var url = URLComponents()
                url.scheme = "mailto"
                url.path = email
                url.queryItems = [URLQueryItem(name: "subject", value: request.subject), URLQueryItem(name: "body", value: request.body)]
                mailtoURL = url.url
            }
        case .directions: break
        }
    }

    /// "Deleted Rent · Undo", shown on the Today screen for a few seconds.
    struct HomeUndo: Identifiable {
        let id = UUID()
        let title: String
        let undo: @Sendable () async throws -> Void
    }
    var homeUndo: HomeUndo?
    var homeError: String?

    /// The item whose delete is waiting for the user's confirmation.
    var deleting: AgendaItem?

    /// ⋯ on a card. Items Sayso only remembers (no calendar access yet) first need access.
    func requestDelete(_ item: AgendaItem) {
        if item.id.hasPrefix("l-") { Task { await connectDay() }; return }
        deleting = item
    }

    /// The user tapped Delete and confirmed.
    func deleteFromHome(_ item: AgendaItem, span: EditSpan) async {
        do {
            let outcome: ActionResult.Outcome
            if item.id.hasPrefix("r-") {
                outcome = try await ReminderDeleteAction.delete(.init(id: String(item.id.dropFirst(2)), title: item.title, due: item.start))
            } else if item.id.hasPrefix("a-") {
                guard let id = UUID(uuidString: String(item.id.dropFirst(2))) else { return }
                try AgendaReader.cancelAlarm(id: id)
                outcome = .completed(undo: nil)
            } else if let id = item.eventID, let start = item.start, let end = item.end {
                let draft = EventDeleteDraft(
                    eventID: id,
                    before: EventSnapshot(title: item.title, start: start, end: end, location: item.detail, isRecurring: item.recurring),
                    span: span)
                outcome = try await EventEditAction.delete(draft)
            } else { return }
            if case .completed(let undo?) = outcome {
                let token = HomeUndo(title: item.title, undo: undo)
                homeUndo = token
                Task {
                    try? await Task.sleep(for: .seconds(7))
                    if homeUndo?.id == token.id { homeUndo = nil }
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            homeError = (error as? LocalizedError)?.errorDescription ?? "Couldn't delete that. Try again."
        }
        await refreshDay()
    }

    func undoHomeDelete() async {
        guard let token = homeUndo else { return }
        homeUndo = nil
        do { try await token.undo() } catch { homeError = "Couldn't restore it. Check the Calendar app." }
        await refreshDay()
    }

    func refreshDay() async { await day.refresh(agent: agent) }
    func connectDay() async { await day.connect(agent: agent) }

    // MARK: Plan my day and Rescue my day

    /// Button or voice. Without Apple Intelligence the manual form takes over.
    func startPlanning(mustDos: String? = nil) {
        guard canSend else { return }
        tab = .chat
        planDay = .now
        append(ChatMessage(role: .user, content: .text("Plan my day")))
        Task { await begin(.planDay(mustDos: mustDos)) }
    }

    func startRescue(minutes: Int) {
        guard canSend else { return }
        tab = .chat
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
        case .propose(let payload):
            clearChoices()
            append(ChatMessage(role: .user, content: .text(choice.label)))
            propose(ActionPlan(actions: [ProposedAction(payload: payload)], transcript: choice.label))
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
                say(await planOpener())
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

    /// Looks at that day first, so the question isn't blind: "You have 5 things tomorrow…".
    private func planOpener() async -> String {
        let cal = Calendar.current
        let name = cal.isDateInToday(planDay) ? "today" : "tomorrow"
        var text = ""
        if AgendaReader.access() == .granted {
            let start = cal.startOfDay(for: planDay)
            let items = await AgendaReader.load(from: start, to: cal.date(byAdding: .day, value: 1, to: start)!)
                .filter { $0.kind == .event && !$0.allDay }
            if !items.isEmpty {
                let first = items.prefix(3).map { "\($0.title) at \($0.start?.formatted(date: .omitted, time: .shortened) ?? "")" }.joined(separator: ", ")
                text = "You already have \(items.count) \(items.count == 1 ? "event" : "events") \(name): \(first)\(items.count > 3 ? " and more" : ""). I'll plan around them.\n\n"
            }
        }
        return text + "What else needs to get done \(name)? Tell me in any order, with how long each takes and any deadlines."
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
        let session = DayPlanSession(mode: .plan, tasks: draftTasks, focus: focus, settings: planner.plan, day: planDay)
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
