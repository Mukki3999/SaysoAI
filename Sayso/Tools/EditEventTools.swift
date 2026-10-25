import EventKit
import Foundation
import FoundationModels

/// Hands the model short handles ("E1") for events instead of long calendar identifiers.
/// A handle only exists if `findEvents` returned it, so the model can't edit an event it hasn't been shown.
actor EventDirectory {
    struct Entry: Sendable {
        let eventID: String
        let snapshot: EventSnapshot
    }

    private var entries: [String: Entry] = [:]
    private var counter = 0

    func register(_ found: [Entry]) -> [String] {
        found.map { entry in
            counter += 1
            let handle = "E\(counter)"
            entries[handle] = entry
            return handle
        }
    }

    func entry(_ handle: String) -> Entry? { entries[handle.uppercased()] }

    func reset() {
        entries = [:]
        counter = 0
    }
}

// MARK: - findEvents (read-only)

struct FindEventsTool: Tool {
    let directory: EventDirectory

    let name = "findEvents"
    let description = "Find calendar events the user wants to change or cancel. Always call this before updateEvent or deleteEvent. Returns matching events with handles."

    @Generable
    struct Arguments {
        @Guide(description: "Words from the event title, like 'dentist'. Empty to match every event in the range")
        var text: String
        @Guide(description: "Start of the range to search, local yyyy-MM-dd'T'HH:mm:ss")
        var from: String
        @Guide(description: "End of the range to search, same format")
        var to: String
        @Guide(description: "True only if the user means every event in the range, like 'cancel everything after 5'")
        var all: Bool
    }

    func call(arguments a: Arguments) async throws -> String {
        guard let from = DateText.parse(a.from), let to = DateText.parse(a.to), to > from else {
            throw ToolError("I couldn't work out which days to look at.")
        }
        try await CalendarAccess.ensureFullEvents()

        let store = EKEventStore()
        let end = min(to, from.addingTimeInterval(31 * 86400))
        let words = a.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 }
        let events = store.events(matching: store.predicateForEvents(withStart: from, end: end, calendars: nil))
            .filter { !$0.isAllDay }
            .filter { e in
                words.isEmpty || words.contains { ((e.title ?? "") + " " + (e.location ?? "")).lowercased().contains($0) }
            }
            .sorted { $0.startDate < $1.startDate }

        if events.isEmpty { return "No events match. Tell the user nothing was found." }
        let lines = events.prefix(12).map { "\($0.title ?? "Untitled"), \(Self.when($0))" }
        if !a.all && events.count > 1 {
            return "Several events match:\n" + lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                + "\nAsk the user which one they mean. Do not call updateEvent or deleteEvent yet."
        }
        if events.count > 12 {
            return "\(events.count) events match, which is too many to change at once. Ask the user to narrow it down."
        }
        let handles = await directory.register(events.map { .init(eventID: $0.eventIdentifier ?? "", snapshot: Self.snapshot($0)) })
        return zip(handles, lines).map { "\($0): \($1)" }.joined(separator: "\n")
    }

    static func snapshot(_ e: EKEvent) -> EventSnapshot {
        EventSnapshot(title: e.title ?? "Untitled", start: e.startDate, end: e.endDate,
                      location: e.location ?? "", isRecurring: e.hasRecurrenceRules)
    }

    private static func when(_ e: EKEvent) -> String {
        let end = e.endDate.formatted(date: .omitted, time: .shortened)
        return "\(DateText.short(e.startDate)) to \(end)" + (e.hasRecurrenceRules ? " (repeats)" : "")
    }
}

// MARK: - updateEvent / deleteEvent (propose only)

struct UpdateEventTool: Tool {
    let collector: PlanCollector
    let directory: EventDirectory

    let name = "updateEvent"
    let description = "Propose a change to one event found with findEvents. Only include what changes."

    @Generable
    struct Arguments {
        @Guide(description: "Handle from findEvents, like 'E1'")
        var id: String
        @Guide(description: "New title, only if renaming")
        var newTitle: String?
        @Guide(description: "New start in local yyyy-MM-dd'T'HH:mm:ss. The event keeps its length unless newEnd is given")
        var newStart: String?
        @Guide(description: "New end, same format, only if the user changed the end or length")
        var newEnd: String?
        @Guide(description: "New location, only if changing it")
        var newLocation: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        guard let entry = await directory.entry(a.id) else {
            throw ToolError("Unknown event \(a.id). Call findEvents first.")
        }
        let before = entry.snapshot
        var after = before
        if let t = a.newTitle, !t.isEmpty { after.title = t }
        if let s = a.newStart {
            guard let start = DateText.parse(s) else { throw ToolError("I couldn't work out the new start time.") }
            after.start = start
            after.end = start.addingTimeInterval(before.end.timeIntervalSince(before.start))   // plain shift
        }
        if let e = a.newEnd {
            guard let end = DateText.parse(e) else { throw ToolError("I couldn't work out the new end time.") }
            after.end = end
        }
        if let l = a.newLocation { after.location = l }
        guard after.end > after.start else { throw ToolError("The end time would be before the start.") }
        guard after != before else { throw ToolError("Nothing would change.") }
        let added = await collector.add(.updateEvent(EventEditDraft(eventID: entry.eventID, before: before, after: after, span: nil)))
        return added ? "Queued the change to “\(before.title)” for the user to approve." : "Already queued."
    }
}

struct DeleteEventTool: Tool {
    let collector: PlanCollector
    let directory: EventDirectory

    let name = "deleteEvent"
    let description = "Propose cancelling one event found with findEvents. Call once per event."

    @Generable
    struct Arguments {
        @Guide(description: "Handle from findEvents, like 'E1'")
        var id: String
    }

    func call(arguments a: Arguments) async throws -> String {
        guard let entry = await directory.entry(a.id) else {
            throw ToolError("Unknown event \(a.id). Call findEvents first.")
        }
        let added = await collector.add(.deleteEvent(EventDeleteDraft(eventID: entry.eventID, before: entry.snapshot, span: nil)))
        return added ? "Queued cancelling “\(entry.snapshot.title)” for the user to approve." : "Already queued."
    }
}

// MARK: - Execution (only reachable through ActionExecutor with an ApprovedPlan)

enum EventEditAction {
    /// The occurrence the user was shown. Repeating events share one identifier, so match the start time too.
    private static func occurrence(_ store: EKEventStore, id: String, snapshot: EventSnapshot) -> EKEvent? {
        let window = store.predicateForEvents(withStart: snapshot.start.addingTimeInterval(-60),
                                              end: snapshot.end.addingTimeInterval(60), calendars: nil)
        let found = store.events(matching: window).first {
            $0.eventIdentifier == id && abs($0.startDate.timeIntervalSince(snapshot.start)) < 60
        }
        return found
    }

    private static func current(_ store: EKEventStore, id: String, before: EventSnapshot) throws -> EKEvent {
        guard let event = occurrence(store, id: id, snapshot: before) else {
            throw ToolError("“\(before.title)” has changed or was removed since you asked.")
        }
        guard event.title == before.title else {
            throw ToolError("“\(before.title)” was renamed since you asked, so nothing was changed.")
        }
        return event
    }

    static func update(_ d: EventEditDraft) async throws -> ActionResult.Outcome {
        try await CalendarAccess.ensureFullEvents()
        let store = EKEventStore()
        let event = try current(store, id: d.eventID, before: d.before)
        let span: EKSpan = d.span == .futureEvents ? .futureEvents : .thisEvent

        event.title = d.after.title
        event.startDate = d.after.start
        event.endDate = d.after.end
        event.location = d.after.location.isEmpty ? nil : d.after.location
        try store.save(event, span: span)

        let box = UnsafeBox((store, event, d.before))
        return .completed(undo: {
            let (store, event, before) = box.value
            event.title = before.title
            event.startDate = before.start
            event.endDate = before.end
            event.location = before.location.isEmpty ? nil : before.location
            try store.save(event, span: span)
        })
    }

    static func delete(_ d: EventDeleteDraft) async throws -> ActionResult.Outcome {
        try await CalendarAccess.ensureFullEvents()
        let store = EKEventStore()
        let event = try current(store, id: d.eventID, before: d.before)
        let span: EKSpan = d.span == .futureEvents ? .futureEvents : .thisEvent

        // Keep enough to put it back.
        let backup = EventBackup(event: event, keepRepeats: span == .futureEvents)
        try store.remove(event, span: span)

        let box = UnsafeBox((store, backup))
        return .completed(undo: {
            let (store, backup) = box.value
            let restored = EKEvent(eventStore: store)
            backup.apply(to: restored)
            try store.save(restored, span: .futureEvents)
        })
    }
}

/// Copy of an event's fields, taken before it is deleted so Undo can recreate it.
private struct EventBackup {
    let title: String, start: Date, end: Date, location: String?, notes: String?, allDay: Bool
    let calendar: EKCalendar?, url: URL?, rules: [EKRecurrenceRule]

    init(event: EKEvent, keepRepeats: Bool) {
        title = event.title ?? ""
        start = event.startDate
        end = event.endDate
        location = event.location
        notes = event.notes
        allDay = event.isAllDay
        calendar = event.calendar
        url = event.url
        rules = keepRepeats ? (event.recurrenceRules ?? []).map {
            EKRecurrenceRule(recurrenceWith: $0.frequency, interval: $0.interval, daysOfTheWeek: $0.daysOfTheWeek,
                             daysOfTheMonth: $0.daysOfTheMonth, monthsOfTheYear: $0.monthsOfTheYear,
                             weeksOfTheYear: $0.weeksOfTheYear, daysOfTheYear: $0.daysOfTheYear,
                             setPositions: $0.setPositions, end: $0.recurrenceEnd)
        } : []
    }

    func apply(to e: EKEvent) {
        e.title = title
        e.startDate = start
        e.endDate = end
        e.location = location
        e.notes = notes
        e.isAllDay = allDay
        e.url = url
        if let calendar { e.calendar = calendar }
        for r in rules { e.addRecurrenceRule(r) }
    }
}
