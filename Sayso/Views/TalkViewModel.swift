import SwiftUI
import MessageUI
import Observation
import PhotosUI
import UIKit

enum TalkState: Equatable {
    case idle, listening, thinking
    case question(String)
    case answer(String)
    case done(String)
    case error(String)
}

struct PendingPhoto: Identifiable {
    let id = UUID()
    let data: Data
    var image: UIImage? { UIImage(data: data) }
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

    init() {
        let life = LifeStore()
        self.life = life
        day = DayStore(life: life)
    }

    enum PlannerStep { case mustDos, focus, behind }

    let planner = PlannerSettings()
    var planSession: DayPlanSession?
    var showManualPlan = false
    var showMenu = false
    var menuSeed: MenuSeed?
    var pendingPhoto: PendingPhoto?
    private var requestID = 0
    private(set) var plannerStep: PlannerStep?
    private var draftTasks: [PlanTask] = []

    private(set) var state: TalkState = .idle
    /// True when the last error was a missing permission, so the error card can offer Settings.
    private(set) var errorNeedsSettings = false
    private(set) var spoken = ""
    var plan: ActionPlan?
    private(set) var results: [ActionResult]?
    private(set) var isExecuting = false
    private let executor = ActionExecutor()
    private var pressing = false
    private var startTask: Task<Void, Never>?

    var waveMode: WaveView.Mode {
        switch state {
        case .listening: .listening
        case .thinking: .thinking
        default: .idle
        }
    }

    /// Tap the mic once for hands-free: Sayso stops itself after you pause. Or hold and release.
    private(set) var handsFree = false
    private var pressStart = Date.now
    private var monitorTask: Task<Void, Never>?

    var caption: String {
        switch state {
        case .listening: handsFree ? "Listening… pause when you're done, or tap to finish" : "Release when you're done"
        case .thinking: ""
        default: "Hold to talk, or tap once"
        }
    }

    func pressBegan() {
        // A tap while hands-free listening means "I'm done".
        if state == .listening, handsFree {
            Task { await finishListening() }
            return
        }
        guard !pressing, canStartTalking else { return }
        pressing = true
        handsFree = false
        pressStart = .now
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        startTask = Task {
            do {
                try await speech.start()
                state = .listening
                startMonitor()
            } catch {
                pressing = false
                handsFree = false
                state = .error(Self.message(for: error))
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

    private static func message(for error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        // Always say what failed, so a report can be acted on.
        return "Something went wrong. Try again.\n\(Diagnostics.describe(error))"
    }

    func dismissError() { state = .idle; errorNeedsSettings = false }

    /// A photo was chosen. Ask what to do with it instead of guessing.
    func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            state = .error("Sayso couldn't open that photo.")
            return
        }
        receivePhoto(data)
    }

    func receivePhoto(_ data: Data) {
        guard canStartTalking else { return }
        pendingPhoto = PendingPhoto(data: data)
    }

    /// Menus go to the Menu Helper. Anything else is read on the iPhone and turned into actions.
    func sendPhoto(_ photo: PendingPhoto, text: String) async {
        pendingPhoto = nil
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        spoken = said.isEmpty ? "Reading your photo…" : said
        state = .thinking
        requestID += 1
        let id = requestID
        do {
            let scan = try await withTimeout(seconds: 30) { try await MenuOCRService.read(photo.data) }
            guard id == requestID, state == .thinking else { return }
            if MenuDetector.looksLikeMenu(scan.lines, userText: said) || said == "What should I eat?" {
                menuSeed = MenuSeed(data: photo.data, text: said == "What should I eat?" ? "" : said)
                showMenu = true
                state = .idle
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
            let outcome = try await withTimeout(seconds: 60) { try await agent.respond(to: prompt, shownAs: label) }
            guard id == requestID, state == .thinking else { return }
            await apply(outcome)
        } catch {
            guard id == requestID else { return }
            errorNeedsSettings = error is PermissionDenied
            state = .error(Self.message(for: error))
        }
    }

    private func apply(_ outcome: AgentOutcome) async {
        switch outcome {
        case .question(let q): state = .question(q)
        case .answer(let a): state = .answer(a)
        case .plan(let plan):
            self.plan = plan
            results = nil
            state = .idle
        case .planner(let intent): await begin(intent)
        }
    }

    /// Stops waiting on the model and returns to the home screen.
    func cancelThinking() {
        requestID += 1
        agent.resetConversation()
        plannerStep = nil
        state = .idle
    }

    // MARK: Plan lifecycle

    func approve() async {
        guard let plan, !isExecuting else { return }
        isExecuting = true
        let approved = plan.approve()
        let ran = await executor.run(approved)
        results = ran
        life.add(ran.filter { if case .failed = $0.outcome { false } else { true } }.map(\.action))
        isExecuting = false
        if ran.count == 1, case .ready(let deferred) = ran[0].outcome {
            performDeferred(deferred, resultID: ran[0].id)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func cancelPlan() {
        Task { await refreshDay() }
        plan = nil
        results = nil
        agent.resetConversation()
        state = .idle
    }

    func closePlan() {
        Task { await refreshDay() }
        let created = results?.filter { if case .failed = $0.outcome { false } else { true } }.count ?? 0
        plan = nil
        results = nil
        agent.resetConversation()
        guard created > 0 else { state = .idle; return }
        state = .done(created == 1 ? "Done" : "\(created) things done")
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if case .done = state { state = .idle }
        }
    }

    func undo(_ id: ActionResult.ID) async {
        guard let i = results?.firstIndex(where: { $0.id == id }),
              case .completed(let undo?) = results?[i].outcome else { return }
        do {
            let actionID = results?[i].action.id
            try await undo()
            if let actionID { life.remove(actionID) }
            results?.remove(at: i)
            Task { await refreshDay() }
        } catch {
            results?[i].outcome = .failed("Couldn't undo. Remove it in the \(results?[i].symbol == "calendar" ? "Calendar" : "system") app.", needsSettings: false)
        }
    }

    /// Composer sheets are presented from TalkView, so they never stack on the confirmation sheet.
    var messageRequest: MessageComposeRequest?
    var emailRequest: EmailComposeRequest?
    var mailtoURL: URL?

    func performDeferred(_ deferred: DeferredAction, resultID: ActionResult.ID) {
        Task {
            do {
                switch deferred {
                case .message(let d):
                    let request = try await MessageAction.prepare(d)
                    guard MFMessageComposeViewController.canSendText() else {
                        throw ToolError("This device can't send text messages.")
                    }
                    plan = nil
                    messageRequest = request
                case .email(let d):
                    let request = try await EmailAction.prepare(d)
                    plan = nil
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
                guard let i = results?.firstIndex(where: { $0.id == resultID }) else { return }
                results?[i].outcome = .failed(error.localizedDescription, needsSettings: error is PermissionDenied)
            }
        }
    }

    private var canStartTalking: Bool {
        switch state {
        case .idle, .done, .question, .answer: true
        case .listening, .thinking, .error: false
        }
    }

    func refreshDay() async { await day.refresh(agent: agent) }
    func connectDay() async { await day.connect(agent: agent) }

    /// Tappable suggestion: same path as speech.
    func ask(_ text: String) async {
        guard canStartTalking else { return }
        await process(text)
    }

    private func process(_ text: String) async {
        spoken = text
        if let step = plannerStep { await handlePlannerAnswer(step, text); return }
        state = .thinking
        requestID += 1
        let id = requestID
        let agent = self.agent
        do {
            let outcome = try await withTimeout(seconds: 60) { try await agent.respond(to: text) }
            guard id == requestID, state == .thinking else { return }   // cancelled or replaced meanwhile
            await apply(outcome)
        } catch {
            guard id == requestID else { return }
            agent.resetConversation()
            errorNeedsSettings = error is PermissionDenied
            state = .error(Self.message(for: error))
        }
    }

    private func finishListening() async {
        guard state == .listening else { return }
        monitorTask?.cancel()
        handsFree = false
        state = .thinking
        let text = await speech.stop()
        guard text.count > 1 else {
            state = .error("Didn't catch that.")
            return
        }
        await process(text)
    }

    // MARK: Plan my day and Rescue my day

    /// Button or voice. Without Apple Intelligence the manual form takes over.
    func startPlanning(mustDos: String? = nil) {
        guard canStartTalking else { return }
        spoken = "Plan my day"
        Task { await begin(.planDay(mustDos: mustDos)) }
    }

    func startRescue(minutes: Int) {
        guard canStartTalking else { return }
        spoken = "I'm \(minutes) minutes behind"
        Task { await begin(.rescueDay(minutesBehind: minutes)) }
    }

    func handle(_ route: IntentRouter.Route) {
        switch route {
        case .plan: startPlanning()
        case .rescue(let minutes): startRescue(minutes: minutes)
        }
    }

    func cancelPlanner() {
        plannerStep = nil
        draftTasks = []
        agent.resetConversation()
        state = .idle
    }

    func chooseFocus(_ focus: FocusPreference) { Task { await handlePlannerAnswer(.focus, focus.rawValue) } }
    func chooseBehind(_ minutes: Int) { Task { await handlePlannerAnswer(.behind, "\(minutes)") } }

    func closePlanSession() {
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
                state = .question("What must get done today? Say them in any order, with how long each takes and any deadlines.")
            }
        case .rescueDay(let minutes):
            if let minutes {
                await buildRescue(behind: minutes)
            } else {
                plannerStep = .behind
                state = .question("How far behind are you?")
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
            do {
                let tasks = try await agent.parseTasks(text)
                guard !tasks.isEmpty else {
                    plannerStep = .mustDos
                    state = .question("I didn't catch any tasks. What must get done today?")
                    return
                }
                draftTasks = tasks
                plannerStep = .focus
                state = .question("Got \(tasks.count) \(tasks.count == 1 ? "task" : "tasks"). When do you focus best?")
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
                state = .question("How many minutes behind are you?")
                return
            }
            await buildRescue(behind: minutes)
        }
    }

    private func buildPlan(focus: FocusPreference) async {
        plannerStep = nil
        planner.focus = focus
        state = .thinking
        let session = DayPlanSession(mode: .plan, tasks: draftTasks, focus: focus, settings: planner.plan)
        session.transcript = spoken
        await present(session)
    }

    private func buildRescue(behind: Int) async {
        plannerStep = nil
        state = .thinking
        let session = DayPlanSession(mode: .rescue(behind: behind), tasks: [], focus: planner.focus, settings: planner.plan)
        await present(session)
    }

    private func present(_ session: DayPlanSession) async {
        do {
            try await session.prepare(agent: agent)
            planSession = session
            state = .idle
        } catch {
            errorNeedsSettings = error is PermissionDenied
            state = .error(Self.message(for: error))
        }
    }
}
