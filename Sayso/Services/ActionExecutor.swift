import EventKit
import Foundation

/// What happened to one approved action.
struct ActionResult: Identifiable {
    enum Outcome {
        /// Finished. `undo` is nil when the system offers no way to take it back.
        case completed(undo: (@Sendable () async throws -> Void)?)
        /// Needs the user to finish in a system screen (composer, Maps). Never sent silently.
        case ready(DeferredAction)
        case failed(String, needsSettings: Bool)
    }

    let id = UUID()
    let action: ProposedAction
    let symbol: String
    let title: String
    var outcome: Outcome
}

enum DeferredAction {
    case message(MessageDraft)
    case email(EmailDraft)
    case directions(DirectionsDraft)

    var isMessage: Bool { if case .message = self { true } else { false } }
}

struct PermissionDenied: LocalizedError {
    let feature: String
    var errorDescription: String? { "Sayso needs \(feature) access. Allow it in Settings." }
}

/// Runs actions. The only entry point takes an `ApprovedPlan`, which can only be made by
/// the user approving on the confirmation sheet.
@MainActor
final class ActionExecutor {
    func run(_ plan: ApprovedPlan) async -> [ActionResult] {
        var results: [ActionResult] = []
        for action in plan.actions {
            results.append(await run(action))
        }
        return results
    }

    private func run(_ action: ProposedAction) async -> ActionResult {
        do {
            let outcome: ActionResult.Outcome
            switch action.payload {
            case .calendar(let d): outcome = try await CalendarEventAction.perform(d)
            case .reminder(let d): outcome = try await ReminderAction.perform(d)
            case .alarm(let d): outcome = try await AlarmAction.perform(d)
            case .timer(let d): outcome = try await TimerAction.perform(d)
            case .message(let d): outcome = .ready(.message(d))
            case .email(let d): outcome = .ready(.email(d))
            case .directions(let d): outcome = .ready(.directions(d))
            case .updateEvent(let d): outcome = try await EventEditAction.update(d)
            case .deleteEvent(let d): outcome = try await EventEditAction.delete(d)
            case .deleteReminder(let d): outcome = try await ReminderDeleteAction.delete(d)
            }
            return ActionResult(action: action, symbol: action.symbol, title: action.card, outcome: outcome)
        } catch {
            let denied = error is PermissionDenied
            return ActionResult(action: action, symbol: action.symbol, title: action.card,
                                outcome: .failed(error.localizedDescription, needsSettings: denied))
        }
    }
}

/// Wraps non-Sendable system objects captured by undo closures.
final class UnsafeBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
