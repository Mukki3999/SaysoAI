import AppIntents
import Observation

/// Where an App Intent leaves a request for the running app to pick up.
@MainActor @Observable
final class IntentRouter {
    enum Route: Equatable {
        case plan
        case rescue(minutes: Int)
    }

    static let shared = IntentRouter()
    var pending: Route?
}

struct PlanMyDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan my day"
    static let description = IntentDescription("Plan today around your calendar. Nothing is added until you approve it.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .plan
        return .result()
    }
}

struct RescueMyDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Rescue my day"
    static let description = IntentDescription("Re-plan the rest of today when you're running behind. Nothing changes until you approve it.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes behind", default: 30)
    var minutesBehind: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .rescue(minutes: max(minutesBehind, 0))
        return .result()
    }
}

struct SaysoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlanMyDayIntent(),
                    phrases: ["Plan my day with \(.applicationName)", "Organize my day in \(.applicationName)"],
                    shortTitle: "Plan my day", systemImageName: "sparkles")
        AppShortcut(intent: RescueMyDayIntent(),
                    phrases: ["Rescue my day with \(.applicationName)", "I'm running behind in \(.applicationName)"],
                    shortTitle: "Rescue my day", systemImageName: "gauge.with.dots.needle.67percent")
    }
}
