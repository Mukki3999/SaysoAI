import AlarmKit
import FoundationModels
import SwiftUI

struct SetAlarmTool: Tool {
    let collector: PlanCollector

    let name = "setAlarm"
    let description = "Propose a real system alarm at a clock time, optionally repeating on certain weekdays. Not for countdowns: use startTimer for those."

    @Generable
    enum Day: String, CaseIterable {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday

        var weekday: Locale.Weekday {
            switch self {
            case .monday: .monday
            case .tuesday: .tuesday
            case .wednesday: .wednesday
            case .thursday: .thursday
            case .friday: .friday
            case .saturday: .saturday
            case .sunday: .sunday
            }
        }
    }

    @Generable
    struct Arguments {
        @Guide(description: "Short label, e.g. 'Wake up'. Use an empty string if none was said")
        var label: String
        @Guide(description: "Time of day in 24-hour HH:mm, e.g. 07:30")
        var time: String
        @Guide(description: "Weekdays to repeat on. Empty for a one-time alarm. 'Weekdays' means monday through friday")
        var repeatDays: [Day]
    }

    func call(arguments a: Arguments) async throws -> String {
        let parts = a.time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
            throw ToolError("I couldn't work out the alarm time “\(a.time)”.")
        }
        let draft = AlarmDraft(label: a.label, hour: parts[0], minute: parts[1],
                               repeatDays: a.repeatDays.map(\.weekday))
        let added = await collector.add(.alarm(draft))
        return added ? "Queued alarm for the user to approve." : "Already queued."
    }
}

// MARK: - Execution (only reachable through ActionExecutor with an ApprovedPlan)

struct SaysoAlarmMetadata: AlarmMetadata {}

/// Explicit stop button: the init without one needs iOS 26.1, and Sayso supports 26.0.
let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")

enum AlarmAction {
    static func authorize() async throws {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized: return
        case .denied: throw PermissionDenied(feature: "alarm")
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { throw PermissionDenied(feature: "alarm") }
        @unknown default: throw PermissionDenied(feature: "alarm")
        }
    }

    static func perform(_ d: AlarmDraft) async throws -> ActionResult.Outcome {
        try await authorize()
        let time = Alarm.Schedule.Relative.Time(hour: d.hour, minute: d.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence = d.repeatDays.isEmpty ? .never : .weekly(d.repeatDays)
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))
        let title = LocalizedStringResource(stringLiteral: d.label.isEmpty ? "Alarm" : d.label)
        let attributes = AlarmAttributes<SaysoAlarmMetadata>(
            presentation: AlarmPresentation(alert: .init(title: title, stopButton: stopButton)),
            tintColor: .primary)
        let id = UUID()
        _ = try await AlarmManager.shared.schedule(
            id: id, configuration: .alarm(schedule: schedule, attributes: attributes))
        return .completed(undo: { try AlarmManager.shared.cancel(id: id) })
    }
}
