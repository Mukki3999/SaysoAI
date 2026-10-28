import Foundation
import Testing
@testable import Sayso

@Suite struct EventCommandTests {
    // Tuesday 2026-10-27, 14:00
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 14))! }

    func parse(_ s: String) -> EventCommand? { EventCommand.parse(s, now: now, calendar: cal) }
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func event(_ id: String, _ title: String, day: Int, hour: Int = 9, recurring: Bool = false) -> EventCandidate {
        EventCandidate(id: id, title: title, location: "", start: at(day, hour), end: at(day, hour + 1), recurring: recurring)
    }

    @Test func plainDelete() {
        #expect(parse("Delete morning skincare routine")?.words == ["skincare", "routine"])
        #expect(parse("cancel my dentist appointment")?.words == ["dentist"])
        #expect(parse("remove the rent event")?.words == ["rent"])
    }

    @Test func screenshotRequest() {
        let c = parse("I have rent due as a recurring even in my calendar can you remove it and all the future events for \"rent\"")
        #expect(c?.words == ["rent"])
        #expect(c?.span == .futureEvents)
    }

    @Test func spanWords() {
        #expect(parse("delete rent and all future events")?.span == .futureEvents)
        #expect(parse("cancel just this standup")?.span == .thisEvent)
        #expect(parse("cancel the dentist")?.span == nil)
    }

    @Test func dayAndTime() {
        let c = parse("delete my 3pm meeting tomorrow")
        #expect(c?.hour == 15)
        #expect(c?.day?.start == at(28, 0))
        #expect(parse("cancel the dentist on friday")?.day?.start == at(30, 0))
        #expect(parse("delete the 9:30 am sync")?.minute == 30)
    }

    @Test func everythingOnADay() {
        let c = parse("cancel everything tomorrow")
        #expect(c?.everything == true)
        #expect(c?.words.isEmpty == true)
        #expect(parse("cancel everything") == nil)      // no day: too dangerous to act on
    }

    @Test func leavesOtherThingsToTheModel() {
        #expect(parse("delete my 7am alarm") == nil)
        #expect(parse("cancel the reminder to call mom") == nil)
        #expect(parse("remove it") == nil)
        #expect(parse("Put an alarm for me so I don't miss my 10am meeting") == nil)
        #expect(parse("what's on tomorrow") == nil)
    }

    @Test func matchesRepeatingEventOnce() {
        let events = (28...31).map { event("skin", "Morning Skincare Routine", day: $0, hour: 7, recurring: true) }
            + [event("dent", "Dentist", day: 28)]
        let m = EventMatcher.match(events, command: parse("delete morning skincare routine")!, now: now, calendar: cal)
        #expect(m.count == 1)
        #expect(m.first?.id == "skin")
        #expect(m.first?.start == at(28, 7))
    }

    @Test func fuzzyWords() {
        let events = [event("a", "Skincare Routine", day: 28), event("b", "Rent due", day: 30)]
        #expect(EventMatcher.match(events, command: parse("delete skin care routine")!, now: now, calendar: cal).map(\.id) == ["a"])
        #expect(EventMatcher.match(events, command: parse("remove rents")!, now: now, calendar: cal).map(\.id) == ["b"])
        #expect(EventMatcher.match(events, command: parse("delete yoga class")!, now: now, calendar: cal).isEmpty)
    }

    @Test func ambiguousStaysAmbiguousUnlessExact() {
        let events = [event("a", "Dentist", day: 28), event("b", "Dentist checkup", day: 29)]
        let c = parse("delete dentist")!
        let m = EventMatcher.match(events, command: c, now: now, calendar: cal)
        #expect(m.count == 2)
        #expect(EventMatcher.exact(m, command: c).map(\.id) == ["a"])
        let both = parse("delete dentist checkup")!
        #expect(EventMatcher.match(events, command: both, now: now, calendar: cal).map(\.id) == ["b"])
    }

    @Test func timeAndDayFilters() {
        let events = [event("a", "Sync", day: 28, hour: 15), event("b", "Sync", day: 28, hour: 10), event("c", "Review", day: 29, hour: 15)]
        let m = EventMatcher.match(events, command: parse("delete my 3pm meeting tomorrow")!, now: now, calendar: cal)
        #expect(m.map(\.id) == ["a"])
    }
}

@Suite struct SuggestionTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 3))! }
    func ev(_ id: String, _ title: String, day: Int, hour: Int) -> EventCandidate {
        EventCandidate(id: id, title: title, location: "", start: cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!,
                       end: cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour + 1))!, recurring: true)
    }

    @Test func emojiTitlesMatch() {
        let events = (28...30).map { ev("night", "🌙 Night Skincare Routine", day: $0, hour: 23) }
            + (28...30).map { ev("morn", "☀️ Morning Skincare Routine", day: $0, hour: 7) }
        let cmd = EventCommand.parse("Can you remove night skincare routine", now: now, calendar: cal)!
        let m = EventMatcher.match(events, command: cmd, now: now, calendar: cal)
        #expect(m.map(\.id) == ["night"])
    }

    @Test func nearMissesAreSuggested() {
        let events = [ev("night", "🌙 Night Skincare Routine", day: 28, hour: 23), ev("x", "Dentist", day: 29, hour: 9)]
        let cmd = EventCommand.parse("delete evening skin routine thing", now: now, calendar: cal)!
        let s = EventMatcher.suggest(events, command: cmd, now: now)
        #expect(s.first?.id == "night")
    }
}
