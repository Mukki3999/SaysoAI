import SwiftUI
import MessageUI
import Observation

enum TalkState: Equatable {
    case idle, listening, thinking
    case question(String)
    case done(String)
    case error(String)
}

@MainActor @Observable
final class TalkViewModel {
    let speech = SpeechService()
    let agent = AgentService()

    private(set) var state: TalkState = .idle
    private(set) var recent: [RecentAction] = []
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

    func pressBegan() {
        guard !pressing, canStartTalking else { return }
        pressing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        startTask = Task {
            do {
                try await speech.start()
                // Finger already lifted while we were starting up.
                if !pressing { await finishListening() } else { state = .listening }
            } catch {
                pressing = false
                state = .error(Self.message(for: error))
            }
        }
    }

    func pressEnded() {
        guard pressing else { return }
        pressing = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await startTask?.value
            if state == .listening { await finishListening() }
        }
    }

    private static func message(for error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        #if DEBUG
        return "Something went wrong: \(error) / \(error.localizedDescription)"
        #else
        return "Something went wrong. Try again."
        #endif
    }

    func dismissError() { state = .idle }

    // MARK: Plan lifecycle

    func approve() async {
        guard let plan, !isExecuting else { return }
        isExecuting = true
        let approved = plan.approve()
        let ran = await executor.run(approved)
        results = ran
        isExecuting = false
        if ran.count == 1, case .ready(let deferred) = ran[0].outcome {
            performDeferred(deferred, resultID: ran[0].id)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        for r in ran {
            if case .failed = r.outcome { continue }
            recent.insert(RecentAction(title: r.title, symbol: r.symbol), at: 0)
        }
    }

    func cancelPlan() {
        plan = nil
        results = nil
        agent.resetConversation()
        state = .idle
    }

    func closePlan() {
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
            let title = results?[i].title
            try await undo()
            results?.remove(at: i)
            recent.removeAll { $0.title == title }
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
        case .idle, .done, .question: true
        case .listening, .thinking, .error: false
        }
    }

    private func finishListening() async {
        let text = await speech.stop()
        guard text.count > 1 else {
            state = .error("Didn't catch that.")
            return
        }
        state = .thinking
        do {
            switch try await agent.respond(to: text) {
            case .question(let q): state = .question(q)
            case .plan(let plan):
                self.plan = plan
                results = nil
                state = .idle
            }
        } catch {
            state = .error(Self.message(for: error))
        }
    }
}
