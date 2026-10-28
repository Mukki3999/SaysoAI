import EventKit
import Foundation

struct ReminderInfo: Sendable, Equatable {
    let id: String
    let title: String
    let due: Date?
}

enum RemindersAccess {
    /// Asks the first time a request needs to read or remove reminders, never before.
    static func ensureFull() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return
        case .denied, .restricted: throw PermissionDenied(feature: "reminders")
        default: break
        }
        guard (try? await EKEventStore().requestFullAccessToReminders()) == true else { throw PermissionDenied(feature: "reminders") }
    }

    nonisolated static func incomplete() async -> [ReminderInfo] {
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: (found ?? []).map {
                    ReminderInfo(id: $0.calendarItemIdentifier, title: $0.title ?? "Reminder",
                                 due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
                })
            }
        }
    }

    /// Reminders whose title has every word (or, failing that, half of them), best first.
    static func match(_ all: [ReminderInfo], words: [String], strict: Bool) -> [ReminderInfo] {
        guard !words.isEmpty else { return [] }
        let scored = all.map { ($0, EventMatcher.score($0.title, words: words)) }
        let hits = strict ? scored.filter { $0.1 == 1 } : scored.filter { $0.1 >= 0.5 }
        return hits.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

enum ReminderDeleteAction {
    static func delete(_ d: ReminderDeleteDraft) async throws -> ActionResult.Outcome {
        try await RemindersAccess.ensureFull()
        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: d.id) as? EKReminder else {
            throw ToolError("“\(d.title)” was already removed.")
        }
        let title = reminder.title ?? d.title
        let due = reminder.dueDateComponents
        let notes = reminder.notes
        let calendar = reminder.calendar
        try store.remove(reminder, commit: true)
        let box = UnsafeBox((store, calendar, title, due, notes))
        return .completed(undo: {
            let (store, calendar, title, due, notes) = box.value
            let restored = EKReminder(eventStore: store)
            restored.title = title
            restored.dueDateComponents = due
            restored.notes = notes
            restored.calendar = calendar ?? store.defaultCalendarForNewReminders()
            try store.save(restored, commit: true)
        })
    }
}
