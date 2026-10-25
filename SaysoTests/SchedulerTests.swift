import Testing
import Foundation
@testable import Sayso

/// Fixed calendar and dates so these never depend on the machine's time zone or today's date.
struct SchedulerTests {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // Monday 2026-10-26
    func t(_ h: Int, _ m: Int = 0, day: Int = 26) -> Date {
        Self.cal.date(from: DateComponents(timeZone: Self.cal.timeZone, year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    var monday: Date { t(0) }
    var early: Date { t(7) }
    let settings = PlanSettings()

    func task(_ title: String, _ minutes: Int, _ priority: TaskPriority = .medium, due: Date? = nil, deep: Bool = false) -> PlanTask {
        PlanTask(title: title, minutes: minutes, priority: priority, deadline: due, deep: deep)
    }

    func plan(_ tasks: [PlanTask], busy: [BusyBlock] = [], focus: FocusPreference = .none, now: Date? = nil,
              day: Date? = nil, force: Bool = false) -> ScheduleResult {
        Scheduler.plan(tasks: tasks, busy: busy, settings: settings, focus: focus,
                       day: day ?? monday, now: now ?? early, force: force, calendar: Self.cal)
    }

    func busy(_ title: String, _ s: Date, _ e: Date) -> BusyBlock { BusyBlock(id: title, title: title, start: s, end: e) }

    // MARK: Planning

    @Test func placesFirstTaskAtStartOfWorkday() {
        let r = plan([task("Write report", 60)])
        #expect(r.blocks.count == 1)
        #expect(r.blocks[0].start == t(9) && r.blocks[0].end == t(10))
    }

    @Test func keepsBufferAroundEvents() {
        let r = plan([task("Email", 30)], busy: [busy("Standup", t(9), t(10))])
        #expect(r.blocks[0].start == t(10, 10))
    }

    @Test func doesNotStartInThePast() {
        let r = plan([task("Email", 30)], now: t(11, 7))
        #expect(r.blocks[0].start == t(11, 10))
    }

    @Test func protectsLunch() {
        // 8 hours of work cannot touch 12:30-13:30.
        let r = plan([task("A", 90), task("B", 90), task("C", 90), task("D", 90)])
        for b in r.blocks { #expect(b.end <= t(12, 30) || b.start >= t(13, 30)) }
    }

    @Test func lunchCanBeTurnedOff() {
        var s = settings
        s.lunchProtected = false
        let r = Scheduler.plan(tasks: [task("A", 90), task("B", 90), task("C", 90)], busy: [], settings: s, focus: .none,
                               day: monday, now: early, calendar: Self.cal)
        #expect(r.blocks.contains { $0.start < t(13, 30) && $0.end > t(12, 30) })
    }

    @Test func deadlineTasksGoBeforeHigherPriorityOnes() {
        let r = plan([task("Big thing", 60, .high), task("Send invoice", 30, .low, due: t(10, 30))])
        let invoice = r.blocks.first { $0.task.title == "Send invoice" }!
        let big = r.blocks.first { $0.task.title == "Big thing" }!
        #expect(invoice.start < big.start)
        #expect(invoice.end <= t(10, 30))
    }

    @Test func higherPriorityGoesFirst() {
        let r = plan([task("Low", 60, .low), task("High", 60, .high)])
        #expect(r.blocks.first { $0.task.title == "High" }!.start == t(9))
    }

    @Test func impossibleDeadlineIsReportedNotHalfScheduled() {
        // Only 9:00-10:00 is available before the 10:00 deadline, but the task needs 2 hours.
        let r = plan([task("Prep deck", 120, .high, due: t(10))])
        #expect(r.blocks.isEmpty)
        #expect(r.leftovers.count == 1)
        #expect(r.leftovers[0].task.minutes == 120)
        #expect(r.leftovers[0].shortenTo == 60)
    }

    @Test func longTasksAreSplitEvenly() {
        #expect(Scheduler.splitSizes(200, settings: settings) == [70, 70, 60])
        #expect(Scheduler.splitSizes(45, settings: settings) == [45])
        let r = plan([task("Deep project", 200)])
        #expect(r.blocks.count == 3)
        #expect(r.blocks.allSatisfy { $0.minutes <= settings.maxChunk })
        #expect(r.blocks.map(\.minutes).reduce(0, +) == 200)
        #expect(r.blocks.allSatisfy { $0.parts == 3 })
        #expect(r.blocks.map(\.part) == [1, 2, 3])
    }

    @Test func deepWorkLandsInTheFocusWindow() {
        let r = plan([task("Design review", 60, deep: true)], focus: .afternoon)
        #expect(r.blocks[0].start == t(13, 30))
    }

    @Test func everydayTasksStayOutOfTheFocusWindow() {
        let r = plan([task("Expenses", 30)], focus: .morning)
        // Morning focus is 8-12, so the everyday task goes after it, not at 9.
        #expect(r.blocks[0].start >= t(12))
    }

    @Test func fallsBackWhenFocusWindowIsFull() {
        let r = plan([task("Deep A", 60, deep: true)], busy: [busy("Offsite", t(8), t(12))], focus: .morning)
        #expect(r.blocks[0].start >= t(12))
    }

    @Test func daysOffAreSkippedUnlessForced() {
        let sunday = t(0, day: 25)
        #expect(plan([task("A", 30)], day: sunday).isDayOff)
        #expect(plan([task("A", 30)], day: sunday).blocks.isEmpty)
        #expect(plan([task("A", 30)], now: t(7, day: 25), day: sunday, force: true).blocks.count == 1)
    }

    @Test func packedDayLeavesWhatDoesNotFit() {
        let meetings = [busy("Workshop", t(9), t(12)), busy("Clients", t(13, 30), t(17, 30))]
        let r = plan([task("Plan", 60, .high), task("Review", 60), task("Quick reply", 15, .low)], busy: meetings)
        // Only a 20-minute gap exists at 12:10 and another after 17:40.
        #expect(r.leftovers.map(\.task.title).sorted() == ["Plan", "Review"])
        #expect(r.blocks.map(\.task.title) == ["Quick reply"])
    }

    @Test func partialPlacementReportsTheRemainder() {
        // Without a deadline, what fits is placed and the rest is left over.
        let r = plan([task("Huge", 600)])
        #expect(!r.blocks.isEmpty)
        let placed = r.blocks.map(\.minutes).reduce(0, +)
        #expect(r.leftovers.first?.task.minutes == 600 - placed)
    }

    @Test func blocksNeverOverlapEachOtherOrEvents() {
        let events = [busy("Standup", t(9, 30), t(10)), busy("Lunch w/ Sam", t(12, 30), t(13, 30)), busy("1:1", t(15), t(15, 30))]
        let r = plan([task("A", 45, .high), task("B", 90, deep: true), task("C", 30), task("D", 120, .low)], busy: events, focus: .morning)
        let all = r.blocks.sorted { $0.start < $1.start }
        for (a, b) in zip(all, all.dropFirst()) { #expect(a.end <= b.start) }
        for blk in all { for e in events { #expect(blk.end <= e.start || blk.start >= e.end) } }
    }

    @Test func everyBlockGetsAReason() {
        let r = plan([task("A", 45), task("B", 30, due: t(11))], busy: [busy("Standup", t(9), t(9, 30))])
        #expect(r.blocks.allSatisfy { !$0.reason.isEmpty })
    }

    @Test func detectsManualMoveConflicts() {
        let events = [busy("Standup", t(9), t(10))]
        #expect(Scheduler.conflicts(Interval(start: t(9, 30), end: t(10, 30)), busy: events, settings: settings, day: monday, calendar: Self.cal) == "Overlaps Standup.")
        #expect(Scheduler.conflicts(Interval(start: t(12, 45), end: t(13, 15)), busy: events, settings: settings, day: monday, calendar: Self.cal) == "That's your lunch.")
        #expect(Scheduler.conflicts(Interval(start: t(7), end: t(8)), busy: events, settings: settings, day: monday, calendar: Self.cal) == "Outside your working hours.")
        #expect(Scheduler.conflicts(Interval(start: t(10, 30), end: t(11)), busy: events, settings: settings, day: monday, calendar: Self.cal) == nil)
    }

    // MARK: Rescue

    func existing(_ id: String, _ title: String, _ s: Date, _ e: Date, _ p: TaskPriority = .medium, due: Date? = nil) -> ExistingBlock {
        ExistingBlock(id: id, task: task(title, Int(e.timeIntervalSince(s) / 60), p, due: due), start: s, end: e)
    }

    func rescue(_ blocks: [ExistingBlock], others: [BusyBlock] = [], now: Date, behind: Int) -> RescueResult {
        Scheduler.rescue(existing: blocks, others: others, settings: settings, focus: .none, now: now, behind: behind, calendar: Self.cal)
    }

    @Test func rescueShrinksToFitAfterRunningLate() throws {
        // 90 minutes of work, 20 minutes lost, and a client call leaves only a 60-minute gap before it.
        let meeting = [busy("Client call", t(16, 30), t(17, 30))]
        let r = rescue([existing("a", "Draft", t(15), t(16, 30), .high)], others: meeting, now: t(15, 20), behind: 20)
        let a = try #require(r.moves.first { $0.id == "a" })
        #expect(a.kind == .shrunk)
        #expect(a.start == t(15, 20) && a.end == t(16, 20))
    }

    @Test func rescueShiftsBlocksPastLaterEvents() throws {
        let blocks = [existing("a", "Draft", t(10), t(11), .high), existing("b", "Review", t(11, 10), t(12, 10))]
        let meeting = [busy("Client call", t(11, 30), t(12))]
        let r = rescue(blocks, others: meeting, now: t(10, 30), behind: 30)
        let a = try #require(r.moves.first { $0.id == "a" })
        let b = try #require(r.moves.first { $0.id == "b" })
        #expect(a.kind == .moved && a.start >= t(10, 30))
        #expect(b.kind == .moved)
        #expect(a.end <= b.start || b.end <= a.start)
        for m in [a, b] { #expect(m.end <= meeting[0].start || m.start >= meeting[0].end) }
    }

    @Test func rescueNeverMovesOtherPeoplesEvents() {
        let meeting = busy("Client call", t(11, 30), t(12))
        let r = rescue([existing("a", "Draft", t(10), t(11)), existing("b", "Review", t(14), t(15))], others: [meeting], now: t(10, 30), behind: 45)
        #expect(r.moves.allSatisfy { ["a", "b"].contains($0.id) })
        for m in r.moves where m.kind != .finished { #expect(m.end <= meeting.start || m.start >= meeting.end) }
    }

    @Test func rescueLeavesBlocksThatStillFit() {
        let r = rescue([existing("late", "Wrap up", t(15), t(16))], now: t(10), behind: 15)
        #expect(r.moves[0].kind == .unchanged)
        #expect(r.moves[0].start == t(15))
    }

    @Test func rescueIgnoresFinishedWork() {
        let r = rescue([existing("done", "Morning email", t(9), t(9, 30))], now: t(11), behind: 20)
        #expect(r.moves[0].kind == .finished)
    }

    @Test func rescueListsWhatNoLongerFits() throws {
        // An hour lost, 15 minutes left before a 5 PM deadline.
        let r = rescue([existing("x", "Ship it", t(16), t(17), .high, due: t(17))], now: t(16, 45), behind: 60)
        let left = try #require(r.leftovers.first)
        #expect(r.leftoverBlockIDs[left.id] == "x")
        #expect(left.task.minutes == 60)
        #expect(left.shortenTo == 15)
    }

    @Test func rescueKeepsDeadlineTasksAheadOfOthers() throws {
        // Not enough room for both: the one with the deadline keeps the slot.
        let blocks = [existing("plain", "Tidy notes", t(16), t(17), .high), existing("due", "Send contract", t(16, 30), t(17, 30), .low, due: t(17, 30))]
        let r = rescue(blocks, now: t(16), behind: 0)
        let due = try #require(r.moves.first { $0.id == "due" })
        #expect(due.end <= t(17, 30))
    }
}
