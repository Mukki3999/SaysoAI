import EventKit
import Foundation

/// Finds the events a spoken or typed "delete …" means, without the language model.
enum EventLookup {
    enum Result {
        case none
        case drafts([EventDeleteDraft])         // one proposal, possibly several events
        case choose([EventDeleteDraft])         // ambiguous: let the user pick
        case tooMany(Int)
    }

    static func resolve(_ command: EventCommand) async throws -> Result {
        try await CalendarAccess.ensureFullEvents()
        let store = EKEventStore()
        let cal = Calendar.current
        let start = command.day?.start ?? cal.startOfDay(for: .now)
        let end = command.day?.end ?? cal.date(byAdding: .day, value: 366, to: start)!

        let candidates = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).map {
            EventCandidate(id: $0.eventIdentifier ?? "", title: $0.title ?? "Untitled", location: $0.location ?? "",
                           start: $0.startDate, end: $0.endDate, recurring: $0.hasRecurrenceRules)
        }.filter { !$0.id.isEmpty }

        var matches = EventMatcher.match(candidates, command: command)
        if !command.everything { matches = EventMatcher.exact(matches, command: command) }
        if matches.isEmpty { return .none }

        let drafts = matches.map { m in
            EventDeleteDraft(eventID: m.id,
                             before: EventSnapshot(title: m.title, start: m.start, end: m.end, location: m.location, isRecurring: m.recurring),
                             span: m.recurring ? command.span : nil)
        }
        if drafts.count == 1 { return .drafts(drafts) }
        if command.everything { return drafts.count > 12 ? .tooMany(drafts.count) : .drafts(drafts) }
        return .choose(Array(drafts.prefix(5)))
    }
}
