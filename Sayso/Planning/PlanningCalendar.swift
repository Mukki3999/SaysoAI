import EventKit
import Foundation

/// What Sayso remembers about each block it put on the calendar, so Rescue can re-plan with the original
/// priority and deadline.
struct StoredBlock: Codable {
    var task: PlanTask
    var part: Int
    var parts: Int
    var day: Date
}

enum PlanStore {
    private static let key = "sayso.plan.blocks"

    static func all() -> [String: StoredBlock] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: StoredBlock].self, from: data) else { return [:] }
        return decoded.filter { $0.value.day > Date.now.addingTimeInterval(-14 * 86400) }
    }

    static func put(_ id: String, _ block: StoredBlock) {
        var map = all()
        map[id] = block
        save(map)
    }

    static func remove(_ id: String) {
        var map = all()
        map[id] = nil
        save(map)
    }

    static func clear() { save([:]) }

    private static func save(_ map: [String: StoredBlock]) {
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Everything the planner does with EventKit. Writes only to the "Sayso Plan" calendar, and refuses to touch
/// any event that isn't in it.
@MainActor
final class PlanningCalendar {
    static let calendarName = "Sayso Plan"
    private static let calendarKey = "sayso.plan.calendarID"
    private let store = EKEventStore()

    // MARK: Reading

    /// Timed events (and reminders with a time) that block the day, excluding the Sayso Plan calendar.
    func busy(on day: Date) async -> [BusyBlock] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let planID = existingPlanCalendar()?.calendarIdentifier

        var out = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay && $0.calendar.calendarIdentifier != planID && $0.availability != .free }
            .map { BusyBlock(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Busy", start: $0.startDate, end: $0.endDate) }

        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            out += await Self.timedReminders(start: start, end: end)
        }
        return out.sorted { $0.start < $1.start }
    }

    private nonisolated static func timedReminders(start: Date, end: Date) async -> [BusyBlock] {
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let blocks = (found ?? []).compactMap { r -> BusyBlock? in
                    guard let comps = r.dueDateComponents, comps.hour != nil,
                          let due = Calendar.current.date(from: comps) else { return nil }
                    return BusyBlock(id: "r-\(r.calendarItemIdentifier)", title: r.title ?? "Reminder",
                                     start: due, end: due.addingTimeInterval(15 * 60))
                }
                continuation.resume(returning: blocks)
            }
        }
    }

    /// Sayso's own blocks on a day, with the task each one came from.
    func saysoBlocks(on day: Date) -> [ExistingBlock] {
        guard let plan = existingPlanCalendar() else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let stored = PlanStore.all()
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [plan]))
            .compactMap { e -> ExistingBlock? in
                guard let id = e.eventIdentifier else { return nil }
                let minutes = Int(e.endDate.timeIntervalSince(e.startDate) / 60)
                let s = stored[id]
                let task = s?.task ?? PlanTask(title: e.title ?? "Task", minutes: minutes)
                return ExistingBlock(id: id, task: task, start: e.startDate, end: e.endDate, part: s?.part ?? 1, parts: s?.parts ?? 1)
            }
            .sorted { $0.start < $1.start }
    }

    // MARK: Writing (called only after the user approves a block)

    typealias Undo = @Sendable () async throws -> Void

    func apply(_ item: PlanItem) throws -> Undo {
        switch item.kind {
        case .add: return try add(item)
        case .move: return try move(item)
        case .remove: return try remove(item)
        }
    }

    private func add(_ item: PlanItem) throws -> Undo {
        let calendar = try planCalendar()
        let event = EKEvent(eventStore: store)
        event.title = item.title
        event.startDate = item.start
        event.endDate = item.end
        event.notes = "Planned by Sayso"
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        if let id = event.eventIdentifier {
            PlanStore.put(id, StoredBlock(task: item.task, part: item.part, parts: item.parts, day: item.start))
        }
        let box = UnsafeBox((store, event))
        return {
            let (store, event) = box.value
            if let id = event.eventIdentifier { PlanStore.remove(id) }
            try store.remove(event, span: .thisEvent)
        }
    }

    private func move(_ item: PlanItem) throws -> Undo {
        let event = try saysoEvent(item.eventID)
        let (oldStart, oldEnd) = (event.startDate!, event.endDate!)
        event.startDate = item.start
        event.endDate = item.end
        try store.save(event, span: .thisEvent)
        if let id = event.eventIdentifier {
            PlanStore.put(id, StoredBlock(task: item.task, part: item.part, parts: item.parts, day: item.start))
        }
        let box = UnsafeBox((store, event))
        return {
            let (store, event) = box.value
            event.startDate = oldStart
            event.endDate = oldEnd
            try store.save(event, span: .thisEvent)
        }
    }

    private func remove(_ item: PlanItem) throws -> Undo {
        let event = try saysoEvent(item.eventID)
        let (title, start, end, calendar) = (event.title ?? item.title, event.startDate!, event.endDate!, event.calendar!)
        let id = event.eventIdentifier
        let stored = id.flatMap { PlanStore.all()[$0] }
        try store.remove(event, span: .thisEvent)
        if let id { PlanStore.remove(id) }
        let box = UnsafeBox((store, calendar))
        return {
            let (store, calendar) = box.value
            let restored = EKEvent(eventStore: store)
            restored.title = title
            restored.startDate = start
            restored.endDate = end
            restored.notes = "Planned by Sayso"
            restored.calendar = calendar
            try store.save(restored, span: .thisEvent)
            if let stored, let newID = restored.eventIdentifier { PlanStore.put(newID, stored) }
        }
    }

    /// Looks up a Sayso block, and refuses anything that isn't in the Sayso Plan calendar.
    private func saysoEvent(_ id: String?) throws -> EKEvent {
        guard let id, let event = store.event(withIdentifier: id) else {
            throw ToolError("That block was changed or removed since the plan was made.")
        }
        guard event.calendar.calendarIdentifier == existingPlanCalendar()?.calendarIdentifier else {
            throw ToolError("Sayso only moves its own blocks.")
        }
        return event
    }

    // MARK: Sayso Plan calendar

    func existingPlanCalendar() -> EKCalendar? {
        let calendars = store.calendars(for: .event)
        if let id = UserDefaults.standard.string(forKey: Self.calendarKey),
           let match = calendars.first(where: { $0.calendarIdentifier == id }) { return match }
        return calendars.first { $0.title == Self.calendarName }
    }

    private func planCalendar() throws -> EKCalendar {
        if let existing = existingPlanCalendar() { return existing }
        // Prefer the account the user already keeps events in; fall back to the local account.
        let sources = [store.defaultCalendarForNewEvents?.source,
                       store.sources.first { $0.sourceType == .local }].compactMap { $0 }
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.calendarName
            calendar.source = source
            if (try? store.saveCalendar(calendar, commit: true)) != nil {
                UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.calendarKey)
                return calendar
            }
        }
        throw ToolError("Couldn't create the “\(Self.calendarName)” calendar. Check that a calendar account is set up in Settings.")
    }

    /// One step to remove everything Sayso planned.
    func removePlanCalendar() throws {
        if let calendar = existingPlanCalendar() { try store.removeCalendar(calendar, commit: true) }
        UserDefaults.standard.removeObject(forKey: Self.calendarKey)
        PlanStore.clear()
    }
}
