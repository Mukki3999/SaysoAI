import Foundation

// Pure scheduling logic. No EventKit, no FoundationModels: everything here is deterministic and unit tested.
// The language model only parses what the user said into `PlanTask`s and words the `reason` lines afterwards.

enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low, medium, high
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var label: String { ["Low", "Medium", "High"][rawValue] }
}

struct PlanTask: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var title: String
    var minutes: Int
    var priority: TaskPriority = .medium
    var deadline: Date?
    /// Needs uninterrupted focus, so it is placed in the user's focus window when possible.
    var deep = false
}

enum FocusPreference: String, Codable, CaseIterable, Sendable {
    case morning, afternoon, evening, none

    var label: String { rawValue.capitalized }

    /// Minutes from midnight, or nil for no preference.
    var window: ClosedRange<Int>? {
        switch self {
        case .morning: 8 * 60...12 * 60
        case .afternoon: 13 * 60...17 * 60
        case .evening: 17 * 60...21 * 60
        case .none: nil
        }
    }
}

struct PlanSettings: Equatable, Codable, Sendable {
    /// Minutes from midnight.
    var workStart = 9 * 60
    var workEnd = 18 * 60
    var buffer = 10
    var lunchProtected = true
    var lunchStart = 12 * 60 + 30
    var lunchEnd = 13 * 60 + 30
    /// `Calendar` weekday numbers (Sunday = 1).
    var daysOff: Set<Int> = [1, 7]
    /// Longest single block. Longer tasks are split.
    var maxChunk = 90
    /// Shortest block worth scheduling.
    var minChunk = 30
}

/// Something already on the calendar that the Scheduler must work around.
struct BusyBlock: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
}

struct Interval: Equatable, Sendable {
    var start: Date
    var end: Date
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct PlacedBlock: Identifiable, Equatable, Sendable {
    var id = UUID()
    var task: PlanTask
    var start: Date
    var end: Date
    var part = 1
    var parts = 1
    /// Facts-based one-liner. The model may reword it; this is the fallback.
    var reason: String

    var title: String { parts > 1 ? "\(task.title) (\(part)/\(parts))" : task.title }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// A task (or the rest of one) that did not fit.
struct Leftover: Identifiable, Equatable, Sendable {
    var id = UUID()
    var task: PlanTask            // `minutes` is what is still unplaced
    var reason: String
    /// The longest block still available, if the user wants to shorten the task to fit. Nil if nothing usable is left.
    var shortenTo: Int?
}

struct ScheduleResult: Equatable, Sendable {
    var blocks: [PlacedBlock] = []
    var leftovers: [Leftover] = []
    var isDayOff = false
}

/// A Sayso block already on the calendar, for Rescue.
struct ExistingBlock: Identifiable, Equatable, Sendable {
    var id: String               // calendar event identifier
    var task: PlanTask
    var start: Date
    var end: Date
    var part = 1
    var parts = 1
}

struct BlockMove: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case unchanged, moved, shrunk, finished }
    var id: String               // same as the ExistingBlock id
    var old: ExistingBlock
    var kind: Kind
    var start: Date
    var end: Date
    var reason: String
}

struct RescueResult: Equatable, Sendable {
    var moves: [BlockMove] = []
    var leftovers: [Leftover] = []
    /// The leftover for a given block id, so the UI can tie "doesn't fit" back to its event.
    var leftoverBlockIDs: [UUID: String] = [:]
}

enum Scheduler {
    // MARK: Planning

    static func plan(tasks: [PlanTask],
                     busy: [BusyBlock],
                     settings: PlanSettings,
                     focus: FocusPreference,
                     day: Date,
                     now: Date,
                     force: Bool = false,
                     calendar cal: Calendar = .current) -> ScheduleResult {
        if !force, settings.daysOff.contains(cal.component(.weekday, from: day)) {
            return ScheduleResult(blocks: [], leftovers: [], isDayOff: true)
        }
        var free = freeIntervals(day: day, settings: settings, busy: busy, now: now, calendar: cal)
        var result = ScheduleResult()
        let focusWindow = focus.window.map { (at($0.lowerBound, day, cal), at($0.upperBound, day, cal)) }
        let dayEnd = at(settings.workEnd, day, cal)

        for task in ordered(tasks) {
            let limit = min(task.deadline ?? dayEnd, dayEnd)
            let allOrNothing = task.deadline != nil
            let before = free
            var sizes = splitSizes(task.minutes, settings: settings)
            var placed: [PlacedBlock] = []

            while !sizes.isEmpty {
                let size = sizes.removeFirst()
                if let start = pickSlot(size: size, free: free, limit: limit, task: task, focus: focusWindow, settings: settings) {
                    let end = start.addingTimeInterval(Double(size) * 60)
                    free = subtract(free, Interval(start: start.addingTimeInterval(-Double(settings.buffer) * 60),
                                                   end: end.addingTimeInterval(Double(settings.buffer) * 60)))
                    placed.append(PlacedBlock(task: task, start: start, end: end, reason: ""))
                    continue
                }
                // No gap that big. Take the largest one worth using and carry the rest forward.
                if size > settings.minChunk, let gap = largestGap(free: free, limit: limit, atLeast: settings.minChunk) {
                    let take = gap.minutes / 5 * 5
                    let end = gap.start.addingTimeInterval(Double(take) * 60)
                    free = subtract(free, Interval(start: gap.start.addingTimeInterval(-Double(settings.buffer) * 60),
                                                   end: end.addingTimeInterval(Double(settings.buffer) * 60)))
                    placed.append(PlacedBlock(task: task, start: gap.start, end: end, reason: ""))
                    sizes.insert(size - take, at: 0)
                    continue
                }
                sizes.insert(size, at: 0)
                break
            }

            let unplaced = sizes.reduce(0, +)
            if unplaced > 0, allOrNothing {
                // A deadline task that can't finish in time is reported whole, not half done.
                free = before
                placed = []
            }
            let remaining = allOrNothing && unplaced > 0 ? task.minutes : unplaced
            if remaining > 0 {
                var left = task
                left.minutes = remaining
                let why = task.deadline.map { "Can't finish before \(clock($0, cal)) with the time you have." }
                    ?? "No room left in your working hours."
                result.leftovers.append(Leftover(task: left, reason: why,
                                                 shortenTo: largestGap(free: free, limit: limit, atLeast: 15).map { $0.minutes / 5 * 5 }))
            }
            let sorted = placed.sorted { $0.start < $1.start }
            for (i, var block) in sorted.enumerated() {
                block.part = i + 1
                block.parts = sorted.count
                block.reason = reason(for: block, busy: busy, settings: settings, focus: focusWindow, cal: cal)
                result.blocks.append(block)
            }
        }
        result.blocks.sort { $0.start < $1.start }
        return result
    }

    // MARK: Rescue

    /// Re-plans what is left of the day. `others` are events that are not Sayso's and never move.
    static func rescue(existing: [ExistingBlock],
                       others: [BusyBlock],
                       settings: PlanSettings,
                       focus: FocusPreference,
                       now: Date,
                       behind: Int,
                       calendar cal: Calendar = .current) -> RescueResult {
        let lagStart = now.addingTimeInterval(-Double(max(behind, 0)) * 60)
        var result = RescueResult()
        var free = freeIntervals(day: now, settings: settings, busy: others, now: now, calendar: cal)
        let focusWindow = focus.window.map { (at($0.lowerBound, now, cal), at($0.upperBound, now, cal)) }
        let dayEnd = at(settings.workEnd, now, cal)

        // Pending work: not yet started, started inside the time lost, or still running.
        var pending: [(block: ExistingBlock, minutes: Int)] = []
        for b in existing {
            if b.end <= lagStart {
                result.moves.append(BlockMove(id: b.id, old: b, kind: .finished, start: b.start, end: b.end, reason: "Already behind you."))
            } else if b.start >= lagStart {
                pending.append((b, Int(b.end.timeIntervalSince(b.start) / 60)))
            } else {
                // Started before the lost time and still running: only the rest is left.
                pending.append((b, max(Int(b.end.timeIntervalSince(now) / 60), 0)))
            }
        }
        pending.sort {
            let a = withMinutes($0.block.task, $0.minutes), b = withMinutes($1.block.task, $1.minutes)
            if goesFirst(a, b) { return true }
            if goesFirst(b, a) { return false }
            return $0.block.start < $1.block.start
        }

        for (block, size) in pending {
            let limit = min(block.task.deadline ?? dayEnd, dayEnd)
            if size == 0 {
                result.moves.append(BlockMove(id: block.id, old: block, kind: .finished, start: block.start, end: block.end, reason: "Already behind you."))
                continue
            }
            // Keep it where it is if the slot is still free.
            let original = Interval(start: block.start, end: block.end)
            if block.start >= now, block.end <= limit, contains(free, original) {
                free = subtract(free, pad(original, settings.buffer))
                result.moves.append(BlockMove(id: block.id, old: block, kind: .unchanged, start: block.start, end: block.end, reason: "Still fits where it is."))
                continue
            }
            // Shift: earliest slot from now, then shrink in 5-minute steps down to half.
            var attempt = size
            let floor = max(15, size / 2 / 5 * 5)
            var placed = false
            while attempt >= floor {
                if let start = pickSlot(size: attempt, free: free, limit: limit, task: block.task, focus: focusWindow, settings: settings) {
                    let end = start.addingTimeInterval(Double(attempt) * 60)
                    free = subtract(free, pad(Interval(start: start, end: end), settings.buffer))
                    let kind: BlockMove.Kind = attempt < size ? .shrunk : .moved
                    let why = attempt < size ? "Shortened from \(size) to \(attempt) min to fit." : "Pushed back to the next open slot."
                    result.moves.append(BlockMove(id: block.id, old: block, kind: kind, start: start, end: end, reason: why))
                    placed = true
                    break
                }
                attempt -= 5
            }
            if !placed {
                var left = block.task
                left.minutes = size
                let why = block.task.deadline.map { "Won't finish before \(clock($0, cal)) now." } ?? "No room left today."
                let leftover = Leftover(task: left, reason: why,
                                        shortenTo: largestGap(free: free, limit: limit, atLeast: 15).map { $0.minutes / 5 * 5 })
                result.leftovers.append(leftover)
                result.leftoverBlockIDs[leftover.id] = block.id
            }
        }
        result.moves.sort { $0.start < $1.start }
        return result
    }

    // MARK: Free time

    /// Open gaps inside working hours, after removing events (with buffers), lunch, and anything already past.
    static func freeIntervals(day: Date, settings: PlanSettings, busy: [BusyBlock], now: Date,
                              calendar cal: Calendar = .current) -> [Interval] {
        var start = at(settings.workStart, day, cal)
        let end = at(settings.workEnd, day, cal)
        if cal.isDate(day, inSameDayAs: now) { start = max(start, roundUp(now, minutes: 5)) }
        guard start < end else { return [] }
        var free = [Interval(start: start, end: end)]
        if settings.lunchProtected, settings.lunchEnd > settings.lunchStart {
            free = subtract(free, Interval(start: at(settings.lunchStart, day, cal), end: at(settings.lunchEnd, day, cal)))
        }
        for b in busy where b.end > b.start {
            free = subtract(free, pad(Interval(start: b.start, end: b.end), settings.buffer))
        }
        return free.filter { $0.minutes >= 15 }
    }

    /// Sizes for a task of `minutes`, split so no block passes `maxChunk` and the pieces are even.
    static func splitSizes(_ minutes: Int, settings: PlanSettings) -> [Int] {
        guard minutes > settings.maxChunk else { return [minutes] }
        let n = Int((Double(minutes) / Double(settings.maxChunk)).rounded(.up))
        let base = Int((Double(minutes) / Double(n) / 5).rounded(.up)) * 5
        var sizes = Array(repeating: base, count: n - 1)
        sizes.append(minutes - base * (n - 1))
        return sizes.filter { $0 > 0 }
    }

    /// Whether `block` can sit at its time without touching `busy`, ignoring buffers. Used when the user moves a block by hand.
    static func conflicts(_ interval: Interval, busy: [BusyBlock], settings: PlanSettings, day: Date, calendar cal: Calendar = .current) -> String? {
        if interval.start < at(settings.workStart, day, cal) || interval.end > at(settings.workEnd, day, cal) {
            return "Outside your working hours."
        }
        if settings.lunchProtected,
           interval.start < at(settings.lunchEnd, day, cal), interval.end > at(settings.lunchStart, day, cal) {
            return "That's your lunch."
        }
        if let hit = busy.first(where: { interval.start < $0.end && interval.end > $0.start }) {
            return "Overlaps \(hit.title)."
        }
        return nil
    }

    // MARK: Internals

    /// Deadlines first (soonest first), then priority, then deep work, then longer tasks.
    static func ordered(_ tasks: [PlanTask]) -> [PlanTask] { tasks.sorted(by: goesFirst) }

    static func goesFirst(_ a: PlanTask, _ b: PlanTask) -> Bool {
        switch (a.deadline, b.deadline) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.priority != b.priority { return a.priority > b.priority }
        if a.deep != b.deep { return a.deep }
        return a.minutes > b.minutes
    }

    private static func pickSlot(size: Int, free: [Interval], limit: Date, task: PlanTask,
                                 focus: (Date, Date)?, settings: PlanSettings) -> Date? {
        let need = Double(size) * 60
        // Earliest start inside each gap that still ends before the limit.
        let fits = free.compactMap { gap -> Interval? in
            let end = min(gap.end, limit)
            return end.timeIntervalSince(gap.start) >= need ? Interval(start: gap.start, end: end) : nil
        }
        guard !fits.isEmpty else { return nil }
        guard let (fs, fe) = focus, task.deadline == nil || task.deep else { return fits[0].start }

        if task.deep {
            // First start that keeps the whole block inside the focus window.
            for gap in fits {
                let s = max(gap.start, fs)
                if s.addingTimeInterval(need) <= min(gap.end, fe) { return s }
            }
            return fits[0].start
        }
        // Everyday tasks stay out of the focus window while there is somewhere else to go.
        for gap in fits {
            if gap.start.addingTimeInterval(need) <= fs || gap.start >= fe { return gap.start }
            // Gap straddles the window: use the part after it.
            if gap.end.timeIntervalSince(max(gap.start, fe)) >= need, gap.start < fe { return fe }
        }
        return fits[0].start
    }

    private static func largestGap(free: [Interval], limit: Date, atLeast: Int) -> Interval? {
        free.compactMap { g -> Interval? in
            let end = min(g.end, limit)
            return end > g.start ? Interval(start: g.start, end: end) : nil
        }
        .filter { $0.minutes >= atLeast }
        .max { $0.minutes < $1.minutes }
    }

    private static func withMinutes(_ t: PlanTask, _ m: Int) -> PlanTask {
        var t = t
        t.minutes = m
        return t
    }

    private static func contains(_ free: [Interval], _ i: Interval) -> Bool {
        free.contains { $0.start <= i.start && $0.end >= i.end }
    }

    private static func pad(_ i: Interval, _ buffer: Int) -> Interval {
        Interval(start: i.start.addingTimeInterval(-Double(buffer) * 60), end: i.end.addingTimeInterval(Double(buffer) * 60))
    }

    static func subtract(_ free: [Interval], _ cut: Interval) -> [Interval] {
        free.flatMap { g -> [Interval] in
            guard cut.start < g.end, cut.end > g.start else { return [g] }
            var out: [Interval] = []
            if cut.start > g.start { out.append(Interval(start: g.start, end: cut.start)) }
            if cut.end < g.end { out.append(Interval(start: cut.end, end: g.end)) }
            return out
        }
    }

    private static func at(_ minute: Int, _ day: Date, _ cal: Calendar) -> Date {
        cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
    }

    private static func roundUp(_ date: Date, minutes: Int) -> Date {
        let step = Double(minutes) * 60
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / step).rounded(.up) * step)
    }

    private static func clock(_ date: Date, _ cal: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.calendar = cal
        style.timeZone = cal.timeZone
        return date.formatted(style)
    }

    private static func reason(for block: PlacedBlock, busy: [BusyBlock], settings: PlanSettings,
                               focus: (Date, Date)?, cal: Calendar) -> String {
        let t = block.task
        let slack = Double(settings.buffer + 5) * 60
        let after = busy.filter { $0.end <= block.start && block.start.timeIntervalSince($0.end) <= slack }.max { $0.end < $1.end }
        let before = busy.filter { $0.start >= block.end && $0.start.timeIntervalSince(block.end) <= slack }.min { $0.start < $1.start }
        var parts: [String] = []

        if let d = t.deadline {
            parts.append("Due \(clock(d, cal)), so it goes early")
        } else if t.deep, let (fs, fe) = focus, block.start >= fs, block.end <= fe {
            parts.append("Deep work in your focus window")
        } else if t.deep, focus != nil {
            parts.append("Focus window was full, so the next quiet gap")
        } else if t.priority == .high {
            parts.append("High priority, placed early")
        } else if let (fs, fe) = focus, block.end <= fs || block.start >= fe {
            parts.append("Keeps your focus hours free")
        } else {
            parts.append("Fits an open gap")
        }
        if let after { parts.append("right after \(after.title)") }
        else if let before { parts.append("just before \(before.title)") }
        if block.parts > 1 { parts.append("part \(block.part) of \(block.parts), so no block runs long") }
        return parts.joined(separator: ", ") + "."
    }
}
