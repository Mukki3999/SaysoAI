import SwiftUI

@main
struct SaysoApp: App {
    @State private var model = TalkViewModel()
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var router = IntentRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Picks up "Plan my day" / "Rescue my day" requests from Shortcuts and voice.
    private func consumeRoute() {
        guard hasOnboarded, let route = router.pending else { return }
        router.pending = nil
        model.handle(route)
    }

    /// Debug-only: lets the simulator, which has no Apple Intelligence, show the main UI.
    private static var skipAvailabilityCheck: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SAYSO_SKIP_AVAILABILITY"] == "1"
        #else
        false
        #endif
    }

    /// Debug-only: shows the approval sheet in the simulator without the on-device model.
    private static func loadDemoPlanIfRequested(_ model: TalkViewModel) {
        #if DEBUG
        let demo = ProcessInfo.processInfo.environment["SAYSO_DEMO_PLAN"]
        let cal = Calendar.current
        if demo == "plan" || demo == "rescue" { model.planSession = DayPlanSession.demo(rescue: demo == "rescue"); return }
        if demo == "edit" {
            let day = cal.startOfDay(for: .now)
            func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
            let dentist = EventSnapshot(title: "Dentist", start: at(15), end: at(16), location: "Smile Care", isRecurring: false)
            var moved = dentist
            moved.start = at(17); moved.end = at(18)
            let sync = EventSnapshot(title: "Team sync", start: at(17, 30), end: at(18), location: "", isRecurring: true)
            model.plan = ActionPlan(actions: [
                ProposedAction(payload: .updateEvent(.init(eventID: "x", before: dentist, after: moved, span: nil))),
                ProposedAction(payload: .deleteEvent(.init(eventID: "y", before: sync, span: nil)))
            ], transcript: "Move my dentist to 5 and cancel the team sync")
            return
        }
        guard demo == "1" else { return }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow)! }
        model.plan = ActionPlan(actions: [
            ProposedAction(payload: .calendar(.init(title: "Lunch with Sam", start: at(12), end: at(13), location: "Blue Bottle Coffee", notes: ""))),
            ProposedAction(payload: .reminder(.init(title: "Call mom", due: at(6), place: "", arriving: true))),
            ProposedAction(payload: .alarm(.init(label: "Wake up", hour: 7, minute: 0, repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday]))),
            ProposedAction(payload: .timer(.init(seconds: 600, label: "Pasta"))),
            ProposedAction(payload: .message(.init(recipient: "Sam Rivera", body: "Running 10 minutes late, order me the usual?"))),
            ProposedAction(payload: .email(.init(recipient: "Alex Chen", subject: "Quarterly numbers", body: "Hi Alex, attached are the numbers we talked about. Let me know if anything looks off before Friday."))),
            ProposedAction(payload: .directions(.init(destination: "Ferry Building San Francisco")))
        ], transcript: "Lunch with Sam tomorrow at noon, remind me to call mom, and set my alarm")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !model.agent.isModelAvailable && !Self.skipAvailabilityCheck {
                    UnsupportedDeviceView(reason: model.agent.unavailableReason, model: model)
                } else if !hasOnboarded {
                    OnboardingView { hasOnboarded = true }
                } else {
                    TalkView(model: model)
                        .task { Self.loadDemoPlanIfRequested(model) }
                }
            }
            .tint(.white)
            .preferredColorScheme(.dark)
            .task { consumeRoute() }
            .onChange(of: router.pending) { consumeRoute() }
            .onChange(of: scenePhase) { if scenePhase == .active { consumeRoute() } }
        }
    }
}
