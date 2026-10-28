import Foundation

/// The simple, common requests, understood in plain Swift. They answer instantly and never fail the way the model can.
/// Anything with more than one part, or anything unclear, returns nil and goes to the model.
enum QuickParser {
    enum Result: Equatable {
        case action(ProposedAction.Payload)
        case agenda(day: Date)
    }

    static func parse(_ text: String, now: Date = .now, calendar cal: Calendar = .current) -> Result? {
        let t = text.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        // More than one request, or a change to something that exists: not for this parser.
        if t.range(of: #"\b(and|then|also|plus|after that)\b|[;]"#, options: .regularExpression) != nil { return nil }
        if t.range(of: EventCommand.verbs, options: .regularExpression) != nil { return nil }
        if t.range(of: #"\b(text|message|email|directions?|navigate)\b"#, options: .regularExpression) != nil { return nil }

        if let r = agenda(t, now: now, cal: cal) { return r }
        if let r = timer(t) { return r }
        if let r = alarm(t) { return r }
        if let r = reminder(t, now: now, cal: cal) { return r }
        return nil
    }

    // MARK: Agenda

    private static func agenda(_ t: String, now: Date, cal: Calendar) -> Result? {
        let ask = #"\b(what'?s on|what is on|what do i have|what have i got|what'?s happening|what'?s my schedule|my schedule|my agenda|am i free|do i have anything|anything on)\b"#
        guard t.range(of: ask, options: .regularExpression) != nil,
              t.range(of: #"\b(plan|help|organi[sz]e)\b"#, options: .regularExpression) == nil else { return nil }
        return .agenda(day: day(in: t, now: now, cal: cal) ?? cal.startOfDay(for: now))
    }

    // MARK: Timer

    private static func timer(_ t: String) -> Result? {
        guard t.range(of: #"\btimer\b"#, options: .regularExpression) != nil else { return nil }
        var seconds = 0
        let words = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30]
        let pattern = #"(\d+(?:\.\d+)?|an?|one|two|three|four|five|ten|fifteen|twenty|thirty)(?: and a half)?\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b"#
        let regex = try! NSRegularExpression(pattern: pattern)
        for m in regex.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
            guard let nr = Range(m.range(at: 1), in: t), let ur = Range(m.range(at: 2), in: t) else { continue }
            let n = Double(t[nr]) ?? Double(words[String(t[nr])] ?? 0)
            let unit = t[ur]
            seconds += Int(n * (unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1))
        }
        if t.contains("half an hour") || t.contains("half hour") { seconds += 1800 }
        guard seconds > 0, seconds <= 24 * 3600 else { return nil }
        return .action(.timer(TimerDraft(seconds: seconds, label: "")))
    }

    // MARK: Alarm

    private static func alarm(_ t: String) -> Result? {
        guard t.range(of: #"\b(alarm|wake me|wake up)\b"#, options: .regularExpression) != nil else { return nil }
        // "so I don't miss my 10am meeting" needs a lead time the user didn't give.
        if t.range(of: #"\b(meeting|appointment|flight|before|miss|class)\b"#, options: .regularExpression) != nil { return nil }
        guard let clock = clock(in: t, defaultsTo: .alarm) else { return nil }
        return .action(.alarm(AlarmDraft(label: "", hour: clock.hour, minute: clock.minute, repeatDays: weekdays(in: t))))
    }

    // MARK: Reminder

    private static func reminder(_ t: String, now: Date, cal: Calendar) -> Result? {
        guard let r = t.range(of: #"\b(remind me|reminder)\s+(to|about|that|of)?\s*"#, options: .regularExpression) else { return nil }
        // Place-based reminders ("when I get home") need the model.
        if t.range(of: #"\b(when i|when we|arrive|arriving|leave|leaving|get home|get to)\b"#, options: .regularExpression) != nil { return nil }
        var rest = String(t[r.upperBound...])
        guard !rest.isEmpty else { return nil }

        let evening = t.range(of: #"\b(tonight|evening|night|afternoon)\b"#, options: .regularExpression) != nil
        let time = clock(in: rest, defaultsTo: evening ? .evening : .event)
        let dayWord = day(in: rest, now: now, cal: cal)

        // The "in 20 minutes" form.
        var due: Date?
        if let m = rest.range(of: #"\bin (\d+)\s*(minutes?|mins?|hours?|hrs?)\b"#, options: .regularExpression) {
            let s = String(rest[m])
            let n = Int(s.filter(\.isNumber)) ?? 0
            due = now.addingTimeInterval(Double(n) * (s.contains("h") ? 3600 : 60))
            rest.removeSubrange(m)
        } else if time != nil || dayWord != nil {
            let base = dayWord ?? cal.startOfDay(for: now)
            let c = time ?? (hour: 9, minute: 0)
            due = cal.date(bySettingHour: c.hour, minute: c.minute, second: 0, of: base)
            // "remind me at 3" when 3 has passed today means tomorrow.
            if dayWord == nil, let d = due, d < now { due = cal.date(byAdding: .day, value: 1, to: d) }
        }

        // The title is what is left once the time words are gone.
        var title = rest
        for pattern in [#"\b(at|by|around|for)\s+\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?"#,
                        #"\b\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)\b"#,
                        #"\b(tomorrow|today|tonight)( (morning|afternoon|evening|night))?\b"#,
                        #"\b(on|this|next)?\s*(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
                        #"\bin the (morning|afternoon|evening)\b"#,
                        #"\b(at )?(noon|midnight)\b"#] {
            title = title.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        title = title.split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        for tail in [" at", " on", " by", " for", " in", " to"] where title.hasSuffix(tail) { title = String(title.dropLast(tail.count)) }
        guard title.count >= 2 else { return nil }
        title = title.prefix(1).uppercased() + title.dropFirst()
        return .action(.reminder(ReminderDraft(title: title, due: due, place: "", arriving: true)))
    }

    // MARK: Pieces

    enum Bare { case alarm, event, evening }

    /// "7am", "6:30 pm", "at 5". Bare hours follow the app's rules: alarms 4–11 are AM; events 1–6 are PM, 7–11 AM.
    static func clock(in text: String, defaultsTo bare: Bare) -> (hour: Int, minute: Int)? {
        guard let r = text.range(of: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?![\d:])"#, options: .regularExpression) else { return nil }
        // Reject numbers that are not times, like "10 minutes" or "5 items".
        let after = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if after.range(of: #"^(minutes?|mins?|hours?|hrs?|seconds?|items?|times?|days?|people)\b"#, options: .regularExpression) != nil { return nil }
        let raw = String(text[r]).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        let digits = raw.filter { $0.isNumber || $0 == ":" }.split(separator: ":").compactMap { Int($0) }
        guard var h = digits.first, (0...23).contains(h) else { return nil }
        let m = digits.count > 1 ? digits[1] : 0
        guard (0...59).contains(m) else { return nil }
        let hasMeridiem = raw.hasSuffix("am") || raw.hasSuffix("pm")
        // A lone number needs "at", "by" or "for" in front, or a colon, to count as a time ("call 2 people" is not one).
        if !hasMeridiem, digits.count < 2,
           text.range(of: "\\b(at|by|for|around|@)\\s*\(digits[0])\\b", options: .regularExpression) == nil { return nil }
        if hasMeridiem {
            guard (1...12).contains(h) else { return nil }
            if h == 12 { h = raw.hasSuffix("pm") ? 12 : 0 } else if raw.hasSuffix("pm") { h += 12 }
        } else if h <= 12 {
            switch bare {
            case .alarm:
                if h == 12 { break }
                guard (4...11).contains(h) else { return nil }       // 1–3 is ambiguous: let the model ask
            case .event:
                if (1...6).contains(h) { h += 12 }
            case .evening:
                if (1...11).contains(h) { h += 12 }
            }
        }
        return (h, m)
    }

    static func weekdays(in text: String) -> [Locale.Weekday] {
        if text.range(of: #"\b(weekdays?|every weekday|work ?days?)\b"#, options: .regularExpression) != nil { return [.monday, .tuesday, .wednesday, .thursday, .friday] }
        if text.range(of: #"\bweekends?\b"#, options: .regularExpression) != nil { return [.saturday, .sunday] }
        if text.range(of: #"\b(every ?day|daily)\b"#, options: .regularExpression) != nil {
            return [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        }
        let all: [(String, Locale.Weekday)] = [("sunday", .sunday), ("monday", .monday), ("tuesday", .tuesday), ("wednesday", .wednesday),
                                               ("thursday", .thursday), ("friday", .friday), ("saturday", .saturday)]
        // Only "every monday" / "on mondays" repeats; a bare "monday" is a one-off.
        guard text.range(of: #"\b(every|each|on) (sun|mon|tues|wednes|thurs|fri|satur)days?\b|\b(sun|mon|tues|wednes|thurs|fri|satur)days\b"#, options: .regularExpression) != nil else { return [] }
        return all.filter { text.contains($0.0) }.map(\.1)
    }

    static func day(in text: String, now: Date, cal: Calendar) -> Date? {
        let today = cal.startOfDay(for: now)
        if text.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil { return cal.date(byAdding: .day, value: 1, to: today) }
        if text.range(of: #"\b(today|tonight)\b"#, options: .regularExpression) != nil { return today }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (i, name) in names.enumerated() where text.range(of: "\\b\(name)\\b", options: .regularExpression) != nil {
            var ahead = (i + 1 - cal.component(.weekday, from: today) + 7) % 7
            if ahead == 0, text.contains("next \(name)") { ahead = 7 }
            return cal.date(byAdding: .day, value: ahead, to: today)
        }
        return nil
    }
}
