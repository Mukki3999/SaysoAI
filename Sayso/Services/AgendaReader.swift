import AlarmKit
import EventKit
import Foundation

struct AgendaItem: Identifiable, Sendable, Equatable {
    enum Kind: Sendable { case event, reminder, alarm }
    let id: String
    let kind: Kind
    let title: String
    let start: Date?      // nil for things with no clock time, like a running timer
    let end: Date?
    let detail: String
    let allDay: Bool
    var eventID: String? = nil      // set for Calendar events, which can be deleted from the home screen
    var recurring = false
}

enum AgendaAccess { case notAsked, granted, denied }

/// Reads the user's day from Calendar, Reminders and the alarms Sayso set. All on-device.
enum AgendaReader {
    static func access() -> AgendaAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    /// Asks for read access to events and reminders. Called only when the user taps "Show my day".
    static func connect() async {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()
    }

    /// One entry per repeating event, at its next occurrence in the coming year.
    static func recurring() async -> [AgendaItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 366, to: start)!
        var seen = Set<String>()
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.hasRecurrenceRules && seen.insert($0.saysoKey).inserted }
            .sorted { $0.startDate < $1.startDate }
            .map { AgendaItem(id: "e-\($0.saysoKey)-\($0.startDate.timeIntervalSince1970)", kind: .event, title: $0.title ?? "Untitled",
                              start: $0.startDate, end: $0.endDate, detail: $0.location ?? "", allDay: $0.isAllDay,
                              eventID: $0.saysoKey, recurring: true) }
    }

    static func cancelAlarm(id: UUID) throws { try AlarmManager.shared.cancel(id: id) }

    static func load(from start: Date, to end: Date) async -> [AgendaItem] {
        let store = EKEventStore()
        var items: [AgendaItem] = []

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            items += events.map {
                AgendaItem(id: "e-\($0.saysoKey)-\($0.startDate.timeIntervalSince1970)",
                           kind: .event, title: $0.title ?? "Untitled", start: $0.startDate, end: $0.endDate,
                           detail: $0.location ?? "", allDay: $0.isAllDay,
                           eventID: $0.saysoKey, recurring: $0.hasRecurrenceRules)
            }
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            items += await reminders(store, endingBefore: end)
        }
        items += alarms(from: start, to: end)

        return items.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    private static func reminders(_ store: EKEventStore, endingBefore end: Date) async -> [AgendaItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let items = (found ?? []).compactMap { r -> AgendaItem? in
                    guard let comps = r.dueDateComponents, let due = Calendar.current.date(from: comps) else { return nil }
                    return AgendaItem(id: "r-\(r.calendarItemIdentifier)", kind: .reminder, title: r.title ?? "Reminder",
                                      start: due, end: nil, detail: "", allDay: comps.hour == nil)
                }
                continuation.resume(returning: items)
            }
        }
    }

    private static func alarms(from start: Date, to end: Date) -> [AgendaItem] {
        guard AlarmManager.shared.authorizationState == .authorized,
              let alarms = try? AlarmManager.shared.alarms else { return [] }
        var items: [AgendaItem] = []
        for alarm in alarms {
            if alarm.state == .countdown || alarm.state == .paused {
                items.append(AgendaItem(id: "a-\(alarm.id)", kind: .alarm, title: "Timer running", start: nil, end: nil,
                                        detail: alarm.state == .paused ? "Paused" : "", allDay: false))
                continue
            }
            guard let schedule = alarm.schedule, let fire = nextFire(of: schedule, after: start), fire < end else { continue }
            var detail = ""
            if case .relative(let r) = schedule, case .weekly(let days) = r.repeats { detail = DateText.days(days) }
            items.append(AgendaItem(id: "a-\(alarm.id)", kind: .alarm, title: "Alarm", start: fire, end: nil,
                                    detail: detail, allDay: false))
        }
        return items
    }

    /// Next time a clock alarm rings, honouring weekly repeats. Used for alarms Sayso set.
    static func nextFire(hour: Int, minute: Int, days: [Locale.Weekday], after date: Date) -> Date? {
        let cal = Calendar.current
        var comps = DateComponents(hour: hour, minute: minute)
        guard !days.isEmpty else { return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) }
        return days.compactMap { day -> Date? in
            comps.weekday = weekdayNumber(day)
            return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
        }.min()
    }

    private static func nextFire(of schedule: Alarm.Schedule, after date: Date) -> Date? {
        let cal = Calendar.current
        switch schedule {
        case .fixed(let d): return d >= date ? d : nil
        case .relative(let r):
            var comps = DateComponents(hour: r.time.hour, minute: r.time.minute)
            guard case .weekly(let days) = r.repeats, !days.isEmpty else {
                return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
            }
            return days.compactMap { day -> Date? in
                comps.weekday = Self.weekdayNumber(day)
                return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
            }.min()
        @unknown default: return nil
        }
    }

    private static func weekdayNumber(_ day: Locale.Weekday) -> Int {
        switch day {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        @unknown default: 1
        }
    }
}
