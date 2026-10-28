import EventKit
import Foundation

/// Finds the events a spoken or typed "delete …" means, without the language model.
enum EventLookup {
    enum Result {
        case none(scanned: Int, suggestions: [EventDeleteDraft])
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
            EventCandidate(id: $0.saysoKey, title: $0.title ?? "Untitled", location: $0.location ?? "",
                           start: $0.startDate, end: $0.endDate, recurring: $0.hasRecurrenceRules)
        }

        func draft(_ m: EventCandidate) -> EventDeleteDraft {
            EventDeleteDraft(eventID: m.id,
                             before: EventSnapshot(title: m.title, start: m.start, end: m.end, location: m.location, isRecurring: m.recurring),
                             span: m.recurring ? command.span : nil)
        }
        // Exact matches only: a loose calendar match must not beat an exact reminder. Near misses come back as suggestions.
        var matches = EventMatcher.match(candidates, command: command, relaxed: false)
        if !command.everything { matches = EventMatcher.exact(matches, command: command) }
        if matches.isEmpty {
            let near = EventMatcher.suggest(candidates, command: command).map(draft)
            return .none(scanned: candidates.count, suggestions: near)
        }

        let drafts = matches.map(draft)
        if drafts.count == 1 { return .drafts(drafts) }
        if command.everything { return drafts.count > 12 ? .tooMany(drafts.count) : .drafts(drafts) }
        return .choose(Array(drafts.prefix(5)))
    }
}
