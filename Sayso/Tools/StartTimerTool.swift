import AlarmKit
import FoundationModels
import SwiftUI

struct StartTimerTool: Tool {
    let collector: PlanCollector

    let name = "startTimer"
    let description = "Propose a countdown timer, e.g. 'timer for 10 minutes'. For a clock time like 7 am use setAlarm instead."

    @Generable
    struct Arguments {
        @Guide(description: "Length in seconds. 10 minutes is 600", .range(1...86400))
        var durationSeconds: Int
        @Guide(description: "Optional label, e.g. 'Pasta'. Empty string if none")
        var label: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        guard a.durationSeconds > 0 else { throw ToolError("A timer needs a length of time.") }
        let added = await collector.add(.timer(TimerDraft(seconds: a.durationSeconds, label: a.label ?? "")))
        return added ? "Queued timer for the user to approve." : "Already queued."
    }
}

// MARK: - Execution (only reachable through ActionExecutor with an ApprovedPlan)

enum TimerAction {
    static func perform(_ d: TimerDraft) async throws -> ActionResult.Outcome {
        try await AlarmAction.authorize()
        let title = LocalizedStringResource(stringLiteral: d.label.isEmpty ? "Timer" : d.label)
        let presentation = AlarmPresentation(
            alert: .init(title: title, stopButton: stopButton),
            countdown: .init(title: title))
        let attributes = AlarmAttributes<SaysoAlarmMetadata>(presentation: presentation, tintColor: .primary)
        let id = UUID()
        _ = try await AlarmManager.shared.schedule(
            id: id, configuration: .timer(duration: TimeInterval(d.seconds), attributes: attributes))
        return .completed(undo: { try AlarmManager.shared.cancel(id: id) })
    }
}
