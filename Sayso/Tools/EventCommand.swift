import Foundation

/// "Delete morning skincare routine", "remove it and all future events for 'rent'", "cancel everything tomorrow".
/// Parsed and matched in plain Swift: the small on-device model is unreliable at find-then-delete, and this must never guess.
struct EventCommand: Equatable, Sendable {
    var words: [String]              // what the user called the event
    var day: DateInterval?           // limits the search to a day
    var hour: Int?                   // "the 3pm meeting"
    var minute: Int = 0
    var everything = false           // "cancel everything tomorrow", "all the X events"
    var span: EditSpan?              // "all future" -> futureEvents, "just this one" -> thisEvent

    static let verbs = #"\b(delete|remove|cancel|erase|get rid of|take off|scrap|clear)\b"#

    private static let noise: Set<String> = [
        "the", "a", "an", "my", "me", "of", "all", "any", "every", "each", "future", "upcoming", "recurring", "repeating",
        "repeat", "repeats", "event", "events", "meeting", "meetings", "appointment", "appointments", "calendar", "from", "in", "on", "at", "please",
        "can", "you", "could", "would", "will", "it", "its", "that", "this", "them", "those", "these", "and", "also", "series",
        "entries", "entry", "occurrence", "occurrences", "instances", "instance", "only", "just", "today", "tomorrow", "tonight",
        "week", "next", "for", "to", "is", "are", "i", "have", "has", "due", "as", "want", "need", "like", "go", "ahead", "one",
        "off", "up", "out", "after", "before", "then", "now", "so", "too", "forever", "everything", "everyone", "rest",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "am", "pm", "morning", "afternoon", "evening"
    ]

    /// Things this parser doesn't handle. The model (or the user) deals with those.
    private static let otherKinds = #"\b(alarms?|reminders?|timers?|texts?|messages?|emails?|notes?|photos?|contacts?)\b"#

    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> EventCommand? {
        let lower = text.lowercased()
        guard let verb = lower.range(of: verbs, options: .regularExpression) else { return nil }
        if lower.range(of: otherKinds, options: .regularExpression) != nil { return nil }

        var cmd = EventCommand(words: [])
        cmd.day = day(in: lower, now: now, calendar: calendar)
        if let t = clock(in: lower) { cmd.hour = t.hour; cmd.minute = t.minute }

        // "all", "every", "everything", "future": the whole series or every match.
        let wantsAll = lower.range(of: #"\b(all|every|everything|future|upcoming|recurring|repeating|series|forever)\b"#, options: .regularExpression) != nil
        if lower.range(of: #"\b(just|only) (this|today'?s?|that)\b|\bthis one\b|\bjust once\b"#, options: .regularExpression) != nil {
            cmd.span = .thisEvent
        } else if wantsAll, lower.range(of: #"\b(future|upcoming|every|all|recurring|repeating|series|forever)\b"#, options: .regularExpression) != nil {
            cmd.span = .futureEvents
        }
        cmd.everything = lower.range(of: #"\b(everything|all (of )?(my |the )?(events|meetings|appointments)|all my)\b"#, options: .regularExpression) != nil

        // The title: quoted text wins, else what follows the verb, else what came before it.
        let quoted = quotedPhrase(in: text)
        let source = quoted ?? String(lower[verb.upperBound...])
        var words = tokens(source)
        if quoted == nil, words.isEmpty { words = tokens(String(lower[..<verb.lowerBound])) }
        cmd.words = words

        // Without a name, a time or a day there is nothing safe to act on.
        if cmd.words.isEmpty && cmd.hour == nil {
            guard cmd.day != nil, cmd.everything else { return nil }
        }
        return cmd
    }

    static func tokens(_ text: String) -> [String] {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: #"\b\d{1,2}(:\d{2})?\s?(am|pm)\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{1,2}[/-]\d{1,2}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.? \d{1,2}(st|nd|rd|th)?\b"#, with: " ", options: .regularExpression)
        return s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !noise.contains($0) && $0.count >= 2 }
    }

    private static func quotedPhrase(in text: String) -> String? {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("‘", "’")]
        for (open, close) in pairs {
            if let a = text.firstIndex(of: open), let b = text[text.index(after: a)...].firstIndex(of: close), a < b {
                let inner = String(text[text.index(after: a)..<b])
                if !inner.trimmingCharacters(in: .whitespaces).isEmpty { return inner }
            }
        }
        return nil
    }

    private static func clock(in text: String) -> (hour: Int, minute: Int)? {
        guard let r = text.range(of: #"\b(\d{1,2})(?::(\d{2}))?\s?(am|pm)\b"#, options: .regularExpression) else { return nil }
        let parts = text[r].replacingOccurrences(of: " ", with: "")
        let digits = parts.dropLast(2).split(separator: ":").compactMap { Int($0) }
        guard var h = digits.first, (1...12).contains(h) else { return nil }
        let pm = parts.hasSuffix("pm")
        if h == 12 { h = pm ? 12 : 0 } else if pm { h += 12 }
        return (h, digits.count > 1 ? digits[1] : 0)
    }

    private static func day(in text: String, now: Date, calendar cal: Calendar) -> DateInterval? {
        let today = cal.startOfDay(for: now)
        func span(_ d: Date) -> DateInterval { DateInterval(start: d, end: cal.date(byAdding: .day, value: 1, to: d)!) }
        if text.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil { return span(cal.date(byAdding: .day, value: 1, to: today)!) }
        if text.range(of: #"\b(today|tonight)\b"#, options: .regularExpression) != nil { return span(today) }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (i, name) in names.enumerated() where text.range(of: "\\b\(name)\\b", options: .regularExpression) != nil {
            var ahead = (i + 1 - cal.component(.weekday, from: today) + 7) % 7
            if ahead == 0, text.contains("next \(name)") { ahead = 7 }
            return span(cal.date(byAdding: .day, value: ahead, to: today)!)
        }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        if let r = text.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.? (\d{1,2})\b"#, options: .regularExpression) {
            let s = String(text[r])
            if let m = months.firstIndex(where: { s.hasPrefix($0) }), let d = Int(s.filter(\.isNumber)), (1...31).contains(d) {
                var c = DateComponents(year: cal.component(.year, from: today), month: m + 1, day: d)
                if let date = cal.date(from: c), date < today { c.year! += 1; if let next = cal.date(from: c) { return span(next) } }
                if let date = cal.date(from: c) { return span(date) }
            }
        }
        return nil
    }
}

// MARK: - Matching

struct EventCandidate: Equatable, Sendable {
    let id: String
    let title: String
    let location: String
    let start: Date
    let end: Date
    let recurring: Bool
}

enum EventMatcher {
    /// One match per event series, using the occurrence the user most likely means.
    static func match(_ events: [EventCandidate], command: EventCommand, now: Date = .now, calendar cal: Calendar = .current) -> [EventCandidate] {
        var pool = events
        if let day = command.day { pool = pool.filter { $0.start < day.end && $0.end > day.start } }
        if let hour = command.hour {
            pool = pool.filter { cal.component(.hour, from: $0.start) == hour && cal.component(.minute, from: $0.start) == command.minute }
        }

        var scored: [(EventCandidate, Double)] = []
        if command.words.isEmpty {
            scored = pool.map { ($0, 1) }
        } else {
            let strict = pool.compactMap { e -> (EventCandidate, Double)? in
                let s = score(e.title, words: command.words)
                return s == 1 ? (e, 1) : nil
            }
            if !strict.isEmpty {
                scored = strict
            } else if command.words.count >= 2 {
                // Allow one word to miss ("skin care routine" vs "Skincare Routine").
                scored = pool.compactMap { e in
                    let s = score(e.title, words: command.words)
                    return s >= Double(command.words.count - 1) / Double(command.words.count) ? (e, s) : nil
                }
            }
        }

        // One occurrence per series: the one in the requested day, else the next one still to come, else the last.
        var bySeries: [String: [EventCandidate]] = [:]
        for (e, _) in scored { bySeries[e.id, default: []].append(e) }
        var picked: [EventCandidate] = bySeries.values.compactMap { group in
            let sorted = group.sorted { $0.start < $1.start }
            if command.day != nil { return sorted.first }
            return sorted.first { $0.end >= now } ?? sorted.last
        }
        // Non-repeating events have no series: keep every one of them.
        picked = picked.sorted { $0.start < $1.start }
        return picked
    }

    /// If one title is exactly what the user said, that is the one they mean.
    static func exact(_ matches: [EventCandidate], command: EventCommand) -> [EventCandidate] {
        guard matches.count > 1, !command.words.isEmpty else { return matches }
        let want = command.words.joined(separator: " ")
        let exact = matches.filter { EventCommand.tokens($0.title).joined(separator: " ") == want || $0.title.lowercased() == want }
        return exact.isEmpty ? matches : exact
    }

    /// 1 when every query word is found in the title.
    static func score(_ title: String, words: [String]) -> Double {
        let titleWords = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty else { return 1 }
        let hits = words.filter { w in titleWords.contains { same($0, w) } }
        return Double(hits.count) / Double(words.count)
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (x, y) = (stem(a), stem(b))
        if x == y { return true }
        if min(x.count, y.count) >= 4, x.hasPrefix(y) || y.hasPrefix(x) { return true }
        if min(x.count, y.count) >= 5, distance(x, y) <= 1 { return true }
        return false
    }

    private static func stem(_ w: String) -> String {
        if w.hasSuffix("ies"), w.count > 4 { return String(w.dropLast(3)) + "y" }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), w.count > 3 { return String(w.dropLast()) }
        return w
    }

    /// Edit distance, early out above 1.
    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > 1 { return 2 }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
