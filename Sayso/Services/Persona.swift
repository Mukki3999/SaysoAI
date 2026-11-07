import Foundation

/// How Sayso talks: warm, quick, a little playful, never robotic. Every line has a few variants so it doesn't repeat itself.
enum Persona {
    private static func pick(_ options: [String]) -> String { options.randomElement() ?? options[0] }

    private static let numbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static func number(_ n: Int) -> String { n < numbers.count ? numbers[n] : "\(n)" }

    /// "a, b, and c"
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    private static func firstName(_ s: String) -> String { s.split(separator: " ").first.map(String.init) ?? s }

    /// A short spoken name for one action: "a text to Ankit", "a reminder to buy milk".
    static func phrase(_ action: ProposedAction) -> String {
        switch action.payload {
        case .calendar(let d): return d.title.isEmpty ? "an event" : "\(d.title) on your calendar"
        case .reminder(let d): return d.title.isEmpty ? "a reminder" : "a reminder to \(d.title.prefix(1).lowercased() + d.title.dropFirst())"
        case .alarm: return "an alarm"
        case .timer(let d): return d.seconds >= 3600 ? "a timer" : "a \(max(1, d.seconds / 60))-minute timer"
        case .message(let d): return "a text to \(firstName(d.recipient))"
        case .email(let d): return "an email to \(firstName(d.recipient))"
        case .directions(let d): return "directions to \(d.destination)"
        case .updateEvent: return "a change to your calendar"
        case .deleteEvent: return "an event to cancel"
        case .deleteReminder: return "a reminder to delete"
        }
    }

    /// What Sayso says when it has something ready for approval.
    @MainActor static func lead(for plan: ActionPlan) -> String {
        let items = plan.actions.map(phrase)
        let n = items.count
        if n == 1 {
            return pick([
                "Got it. Here's one thing to approve: \(items[0]).",
                "Sure thing. I've got \(items[0]) ready. Take a look and tap approve.",
                "On it. Just \(items[0]). Look good?"
            ])
        }
        let count = number(n)
        return pick([
            "Sure thing. Here are \(count) things to approve: \(list(items)).",
            "You got it. I lined up \(count) things: \(list(items)). Give them a look and hit approve.",
            "Alright, \(count) things are ready for you: \(list(items)). Approve whenever you're ready."
        ])
    }

    static func done(count: Int) -> String {
        count > 1
            ? pick(["All \(number(count)) done. Anything else?", "Done and dusted. That's \(number(count)) things off your list.", "Boom, all \(number(count)) are set."])
            : pick(["Done. All set.", "Done and dusted.", "Boom, that's done. Anything else?"])
    }

    static let openingComposer = [
        "Opening it now. You hit send when you're happy with it.",
        "Here it is. Give it a read, then tap send yourself."
    ]
    static func composerOpening() -> String { pick(openingComposer) }

    static func cancelled() -> String {
        pick(["No problem, scrapped it.", "Okay, never mind that one.", "Consider it gone."])
    }

    /// Spoken summary of a day's agenda.
    static func agenda(day: String, items: [AgendaItem]) -> String {
        let n = items.count
        guard n > 0 else { return "\(day) is wide open. Nothing on it." }
        var line = "\(day) you've got \(number(n)) \(n == 1 ? "thing" : "things")."
        if let first = items.first {
            if let start = first.start, !first.allDay {
                line += " First up, \(first.title) at \(start.formatted(date: .omitted, time: .shortened))."
            } else {
                line += " First up, \(first.title)."
            }
        }
        return line
    }
}
