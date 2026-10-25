import Foundation
import Observation

/// One proposed change to the calendar, shown as a block on the plan sheet.
struct PlanItem: Identifiable {
    enum Kind { case add, move, remove }
    enum Status: Equatable { case pending, committed, dropped, failed(String) }

    let id = UUID()
    var kind: Kind
    var title: String
    var start: Date
    var end: Date
    var oldStart: Date?
    var oldEnd: Date?
    var eventID: String?          // the existing Sayso event, for move and remove
    var task: PlanTask
    var part = 1
    var parts = 1
    var reason: String
    var status: Status = .pending
    var undo: (@Sendable () async throws -> Void)?
    var moveError: String?
}

struct LeftoverState: Identifiable {
    enum Choice: Equatable { case undecided, tomorrow(Date), shortened(Int), dropped }
    var leftover: Leftover
    var blockID: String?          // the Sayso event this came from, in Rescue
    var choice: Choice = .undecided
    var note: String?
    var id: UUID { leftover.id }
}

/// Timeline entry for the before/after view.
struct TimelineEntry: Identifiable {
    enum Style { case event, proposed, committed, kept, old }
    let id: String
    var title: String
    var start: Date
    var end: Date
    var style: Style
}

@MainActor @Observable
final class DayPlanSession: Identifiable {
    enum Mode: Equatable { case plan, rescue(behind: Int) }

    let id = UUID()
    let mode: Mode
    let settings: PlanSettings
    let focus: FocusPreference
    let tasks: [PlanTask]
    let day: Date
    let now: Date

    private(set) var busy: [BusyBlock] = []
    private(set) var before: [ExistingBlock] = []        // Sayso blocks as they are now (Rescue)
    private(set) var keptBlocks: [ExistingBlock] = []    // Rescue blocks that don't change
    private(set) var finishedCount = 0
    private(set) var isDayOff = false
    private(set) var isLoaded = false
    var items: [PlanItem] = []
    var leftovers: [LeftoverState] = []
    var transcript = ""

    private let calendar = PlanningCalendar()
    private var forced = false

    init(mode: Mode, tasks: [PlanTask], focus: FocusPreference, settings: PlanSettings, day: Date = .now) {
        self.mode = mode
        self.tasks = tasks
        self.focus = focus
        self.settings = settings
        self.day = Calendar.current.startOfDay(for: day)
        self.now = .now
    }

    var isRescue: Bool { if case .rescue = mode { true } else { false } }

    // MARK: Building

    /// Reads the calendar and runs the Scheduler. Throws `PermissionDenied` if the calendar can't be read.
    func prepare(agent: AgentService?) async throws {
        try await CalendarAccess.ensureFullEvents()
        switch mode {
        case .plan:
            try await buildPlan()
            if let agent, !items.isEmpty { await rewordReasons(agent) }
        case .rescue(let behind):
            try await buildRescue(behind: behind)
        }
        isLoaded = true
    }

    private func buildPlan() async throws {
        busy = await calendar.busy(on: day)
        // Blocks already in the Sayso Plan calendar are respected, not duplicated.
        let existing = calendar.saysoBlocks(on: day)
        let blocked = busy + existing.map { BusyBlock(id: $0.id, title: $0.task.title, start: $0.start, end: $0.end) }
        let result = Scheduler.plan(tasks: tasks, busy: blocked, settings: settings, focus: focus, day: day, now: now, force: forced)
        isDayOff = result.isDayOff
        keptBlocks = existing
        items = result.blocks.map(Self.item(for:))
        leftovers = result.leftovers.map { LeftoverState(leftover: $0) }
    }

    private func buildRescue(behind: Int) async throws {
        before = calendar.saysoBlocks(on: now)
        guard !before.isEmpty else {
            throw ToolError("There's no Sayso plan for today yet. Say “plan my day” first.")
        }
        busy = await calendar.busy(on: now)
        let result = Scheduler.rescue(existing: before, others: busy, settings: settings, focus: focus, now: now, behind: behind)
        var out: [PlanItem] = []
        for m in result.moves {
            switch m.kind {
            case .finished: finishedCount += 1
            case .unchanged: keptBlocks.append(m.old)
            case .moved, .shrunk:
                out.append(PlanItem(kind: .move, title: m.old.task.title, start: m.start, end: m.end,
                                    oldStart: m.old.start, oldEnd: m.old.end, eventID: m.id,
                                    task: m.old.task, part: m.old.part, parts: m.old.parts, reason: m.reason))
            }
        }
        items = out
        leftovers = result.leftovers.map { LeftoverState(leftover: $0, blockID: result.leftoverBlockIDs[$0.id]) }
    }

    /// Lets the plan be rebuilt on a day marked as a day off.
    func planAnyway() async {
        forced = true
        try? await buildPlan()
    }

    private static func item(for b: PlacedBlock) -> PlanItem {
        PlanItem(kind: .add, title: b.title, start: b.start, end: b.end, task: b.task, part: b.part, parts: b.parts, reason: b.reason)
    }

    private func rewordReasons(_ agent: AgentService) async {
        let facts = items.map { "\($0.title), \(DateText.clock($0.start)) to \(DateText.clock($0.end)): \($0.reason)" }
        guard let lines = await agent.rewordReasons(facts) else { return }
        for i in items.indices { items[i].reason = lines[i] }
    }

    // MARK: Timeline

    func entries(side: Bool) -> [TimelineEntry] {
        // side false = before, true = after
        var out = busy.map { TimelineEntry(id: "b-\($0.id)", title: $0.title, start: $0.start, end: $0.end, style: .event) }
        let cal = Calendar.current
        func today(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: day) }
        if !side {
            out += before.map { TimelineEntry(id: "o-\($0.id)", title: $0.task.title, start: $0.start, end: $0.end, style: .old) }
            if !isRescue {
                out += keptBlocks.map { TimelineEntry(id: "k-\($0.id)", title: $0.task.title, start: $0.start, end: $0.end, style: .kept) }
            }
        } else {
            out += keptBlocks.map { TimelineEntry(id: "k-\($0.id)", title: $0.task.title, start: $0.start, end: $0.end, style: .kept) }
            for i in items where i.status != .dropped && i.kind != .remove && today(i.start) {
                out.append(TimelineEntry(id: "i-\(i.id)", title: i.title, start: i.start, end: i.end,
                                         style: i.status == .committed ? .committed : .proposed))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    var pendingCount: Int { items.filter { $0.status == .pending }.count }
    var committedCount: Int { items.filter { $0.status == .committed }.count }
    var hasUndecidedLeftovers: Bool { leftovers.contains { $0.choice == .undecided } }

    // MARK: Per-block controls

    func drop(_ id: PlanItem.ID) { setStatus(id, .dropped) }
    func restore(_ id: PlanItem.ID) { setStatus(id, .pending) }

    private func setStatus(_ id: PlanItem.ID, _ status: PlanItem.Status) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status != .committed else { return }
        items[i].status = status
    }

    /// Why a block can't go at `start`, or nil if it can.
    func conflict(for id: PlanItem.ID, startingAt start: Date) -> String? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let length = item.end.timeIntervalSince(item.start)
        let interval = Interval(start: start, end: start.addingTimeInterval(length))
        var others = busy + keptBlocks.map { BusyBlock(id: $0.id, title: $0.task.title, start: $0.start, end: $0.end) }
        others += items.filter { $0.id != id && $0.status != .dropped && $0.kind != .remove }
            .map { BusyBlock(id: $0.id.uuidString, title: $0.title, start: $0.start, end: $0.end) }
        return Scheduler.conflicts(interval, busy: others, settings: settings, day: item.start)
    }

    func move(_ id: PlanItem.ID, to start: Date) {
        guard conflict(for: id, startingAt: start) == nil,
              let i = items.firstIndex(where: { $0.id == id }), items[i].status != .committed else { return }
        let length = items[i].end.timeIntervalSince(items[i].start)
        items[i].start = start
        items[i].end = start.addingTimeInterval(length)
        items[i].reason = "Moved by you."
    }

    // MARK: Committing (only ever called from a button the user taps)

    func commit(_ id: PlanItem.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status == .pending else { return }
        do {
            items[i].undo = try calendar.apply(items[i])
            items[i].status = .committed
        } catch {
            items[i].status = .failed(error.localizedDescription)
        }
    }

    func commitAll() {
        for item in items where item.status == .pending { commit(item.id) }
    }

    func undo(_ id: PlanItem.ID) async {
        guard let i = items.firstIndex(where: { $0.id == id }), let undo = items[i].undo else { return }
        do {
            try await undo()
            items[i].undo = nil
            items[i].status = .pending
        } catch {
            items[i].status = .failed("Couldn't undo. Remove it from the “\(PlanningCalendar.calendarName)” calendar.")
        }
    }

    func undoAll() async {
        for item in items where item.status == .committed { await undo(item.id) }
    }

    // MARK: Things that no longer fit

    func resolve(_ id: LeftoverState.ID, _ choice: LeftoverState.Choice) async {
        guard let li = leftovers.firstIndex(where: { $0.id == id }) else { return }
        let state = leftovers[li]
        switch choice {
        case .undecided: break
        case .dropped:
            if let blockID = state.blockID, let old = before.first(where: { $0.id == blockID }) {
                items.append(PlanItem(kind: .remove, title: old.task.title, start: old.start, end: old.end,
                                      oldStart: old.start, oldEnd: old.end, eventID: blockID, task: old.task,
                                      part: old.part, parts: old.parts, reason: "Removed because it no longer fits."))
            }
            leftovers[li].choice = .dropped
        case .tomorrow:
            await moveToNextWorkDay(li)
        case .shortened(let minutes):
            shorten(li, to: minutes)
        }
    }

    private func moveToNextWorkDay(_ li: Int) async {
        let state = leftovers[li]
        let cal = Calendar.current
        var next = cal.date(byAdding: .day, value: 1, to: day)!
        for _ in 0..<7 where settings.daysOff.contains(cal.component(.weekday, from: next)) {
            next = cal.date(byAdding: .day, value: 1, to: next)!
        }
        let blocked = await calendar.busy(on: next) + calendar.saysoBlocks(on: next).map {
            BusyBlock(id: $0.id, title: $0.task.title, start: $0.start, end: $0.end)
        }
        let result = Scheduler.plan(tasks: [state.leftover.task], busy: blocked, settings: settings, focus: focus,
                                    day: next, now: next, force: true)
        guard !result.blocks.isEmpty else {
            leftovers[li].note = "No room on \(next.formatted(.dateTime.weekday(.wide))) either."
            return
        }
        addPlaced(result.blocks, for: state)
        leftovers[li].choice = .tomorrow(next)
        leftovers[li].note = nil
    }

    private func shorten(_ li: Int, to minutes: Int) {
        let state = leftovers[li]
        var task = state.leftover.task
        task.minutes = minutes
        var blocked = busy + keptBlocks.map { BusyBlock(id: $0.id, title: $0.task.title, start: $0.start, end: $0.end) }
        blocked += items.filter { $0.status != .dropped && $0.kind != .remove }
            .map { BusyBlock(id: $0.id.uuidString, title: $0.title, start: $0.start, end: $0.end) }
        let result = Scheduler.plan(tasks: [task], busy: blocked, settings: settings, focus: focus, day: day, now: now, force: true)
        guard !result.blocks.isEmpty else {
            leftovers[li].note = "That doesn't fit either."
            return
        }
        addPlaced(result.blocks, for: state)
        leftovers[li].choice = .shortened(minutes)
        leftovers[li].note = nil
    }

    /// In Rescue the first block takes over the existing event; anything else is added.
    private func addPlaced(_ blocks: [PlacedBlock], for state: LeftoverState) {
        for (n, b) in blocks.enumerated() {
            if n == 0, let blockID = state.blockID, let old = before.first(where: { $0.id == blockID }) {
                items.append(PlanItem(kind: .move, title: b.title, start: b.start, end: b.end, oldStart: old.start, oldEnd: old.end,
                                      eventID: blockID, task: b.task, part: old.part, parts: old.parts, reason: b.reason))
            } else {
                items.append(Self.item(for: b))
            }
        }
    }
}

#if DEBUG
extension DayPlanSession {
    /// Simulator-only: runs the real Scheduler on sample events so the sheet can be checked without a calendar.
    static func demo(rescue: Bool) -> DayPlanSession {
        let cal = Calendar.current
        let day = cal.startOfDay(for: .now)
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        let busy = [BusyBlock(id: "1", title: "Standup", start: at(9, 30), end: at(10)),
                    BusyBlock(id: "2", title: "Design review", start: at(14), end: at(15)),
                    BusyBlock(id: "3", title: "1:1 with Sam", start: at(16), end: at(16, 30))]
        let tasks = [PlanTask(title: "Finish Q4 deck", minutes: 120, priority: .high, deadline: at(17), deep: true),
                     PlanTask(title: "Reply to emails", minutes: 30),
                     PlanTask(title: "Gym", minutes: 60, priority: .low),
                     PlanTask(title: "Write launch post", minutes: 90, deep: true)]
        let s = DayPlanSession(mode: rescue ? .rescue(behind: 45) : .plan, tasks: tasks, focus: .morning, settings: PlanSettings())
        s.loadDemo(busy: busy, now: at(rescue ? 11 : 8), rescue: rescue)
        return s
    }

    fileprivate func loadDemo(busy: [BusyBlock], now: Date, rescue: Bool) {
        self.busy = busy
        if !rescue {
            let r = Scheduler.plan(tasks: tasks, busy: busy, settings: settings, focus: focus, day: day, now: now, force: true)
            items = r.blocks.map { PlanItem(kind: .add, title: $0.title, start: $0.start, end: $0.end, task: $0.task, part: $0.part, parts: $0.parts, reason: $0.reason) }
            leftovers = r.leftovers.map { LeftoverState(leftover: $0) }
        } else {
            let r = Scheduler.plan(tasks: tasks, busy: busy, settings: settings, focus: focus, day: day, now: now.addingTimeInterval(-3 * 3600), force: true)
            before = r.blocks.map { ExistingBlock(id: $0.id.uuidString, task: $0.task, start: $0.start, end: $0.end, part: $0.part, parts: $0.parts) }
            let res = Scheduler.rescue(existing: before, others: busy, settings: settings, focus: focus, now: now, behind: 45)
            for m in res.moves {
                switch m.kind {
                case .finished: finishedCount += 1
                case .unchanged: keptBlocks.append(m.old)
                default: items.append(PlanItem(kind: .move, title: m.old.task.title, start: m.start, end: m.end, oldStart: m.old.start, oldEnd: m.old.end, eventID: m.id, task: m.old.task, reason: m.reason))
                }
            }
            leftovers = res.leftovers.map { LeftoverState(leftover: $0, blockID: res.leftoverBlockIDs[$0.id]) }
        }
        isLoaded = true
    }
}
#endif
