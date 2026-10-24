import Foundation
import Observation

// MARK: - Drafts (editable fields shown on the confirmation sheet)

struct CalendarEventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date?
    var location: String
    var notes: String
}

struct ReminderDraft: Equatable, Sendable {
    var title: String
    var due: Date?
    var place: String          // empty = no location trigger
    var arriving: Bool
}

struct AlarmDraft: Equatable, Sendable {
    var label: String
    var hour: Int
    var minute: Int
    var repeatDays: [Locale.Weekday]
}

struct TimerDraft: Equatable, Sendable {
    var seconds: Int
    var label: String
}

struct MessageDraft: Equatable, Sendable {
    var recipient: String
    var body: String
}

struct EmailDraft: Equatable, Sendable {
    var recipient: String
    var subject: String
    var body: String
}

struct DirectionsDraft: Equatable, Sendable {
    var destination: String
}

// MARK: - Proposed action

struct ProposedAction: Identifiable, Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case calendar(CalendarEventDraft)
        case reminder(ReminderDraft)
        case alarm(AlarmDraft)
        case timer(TimerDraft)
        case message(MessageDraft)
        case email(EmailDraft)
        case directions(DirectionsDraft)
    }

    let id = UUID()
    var payload: Payload

    var kindLabel: String {
        switch payload {
        case .calendar: "Calendar"
        case .reminder: "Reminder"
        case .alarm: "Alarm"
        case .timer: "Timer"
        case .message: "Message"
        case .email: "Email"
        case .directions: "Directions"
        }
    }

    var symbol: String {
        switch payload {
        case .calendar: "calendar"
        case .reminder: "checklist"
        case .alarm: "alarm"
        case .timer: "timer"
        case .message: "message"
        case .email: "envelope"
        case .directions: "arrow.triangle.turn.up.right.diamond"
        }
    }

    /// One-line description, e.g. "Lunch with Sam, Fri 12:00 PM".
    var summary: String {
        switch payload {
        case .calendar(let d):
            return "\(d.title), \(DateText.short(d.start))"
        case .reminder(let d):
            var parts = [d.title]
            if let due = d.due { parts.append(DateText.short(due)) }
            if !d.place.isEmpty { parts.append("\(d.arriving ? "at" : "leaving") \(d.place)") }
            return parts.joined(separator: ", ")
        case .alarm(let d):
            var s = DateText.clock(hour: d.hour, minute: d.minute)
            if !d.label.isEmpty { s = "\(d.label), \(s)" }
            if !d.repeatDays.isEmpty { s += " · " + DateText.days(d.repeatDays) }
            return s
        case .timer(let d):
            let t = DateText.duration(d.seconds)
            return d.label.isEmpty ? t : "\(d.label), \(t)"
        case .message(let d):
            return "To \(d.recipient): \(d.body)"
        case .email(let d):
            return "To \(d.recipient): \(d.subject)"
        case .directions(let d):
            return d.destination
        }
    }

    var card: String { "\(kindLabel): \(summary)" }
}

// MARK: - Collector (written to by tools, off the main actor)

/// Tools append here instead of acting. Nothing in this file or in any Tool touches
/// EventKit, AlarmKit, Contacts or MessageUI.
actor PlanCollector {
    private var actions: [ProposedAction] = []

    func add(_ payload: ProposedAction.Payload) -> Bool {
        let action = ProposedAction(payload: payload)
        // The model sometimes repeats an identical call.
        if actions.contains(where: { $0.payload == payload }) { return false }
        actions.append(action)
        return true
    }

    func drain() -> [ProposedAction] {
        defer { actions = [] }
        return actions
    }

    func reset() { actions = [] }
}

// MARK: - Plan shown to the user

@MainActor @Observable
final class ActionPlan: Identifiable {
    var actions: [ProposedAction]
    let transcript: String

    init(actions: [ProposedAction], transcript: String) {
        self.actions = actions
        self.transcript = transcript
    }

    func update(_ action: ProposedAction) {
        guard let i = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[i] = action
    }

    func remove(_ id: ProposedAction.ID) { actions.removeAll { $0.id == id } }

    /// The only way to get an `ApprovedPlan`, which is the only thing `ActionExecutor` accepts.
    func approve() -> ApprovedPlan { ApprovedPlan(actions: actions) }
}

/// Proof that the user tapped Approve. Only `ActionPlan.approve()` can create one.
struct ApprovedPlan: Sendable {
    let actions: [ProposedAction]
    fileprivate init(actions: [ProposedAction]) { self.actions = actions }
}

// MARK: - Date helpers

enum DateText {
    static func short(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "Today \(time)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 99
        if (0..<7).contains(days) { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) \(time)"
    }

    static func clock(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func days(_ days: [Locale.Weekday]) -> String {
        let order: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let set = Set(days)
        if set == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
        if set == [.saturday, .sunday] { return "Weekends" }
        if set.count == 7 { return "Every day" }
        let names = Calendar.current.shortWeekdaySymbols
        return order.enumerated().filter { set.contains($0.element) }.map { names[$0.offset] }.joined(separator: " ")
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) sec") }
        return parts.joined(separator: " ")
    }

    /// Parses the local date-time strings the model is told to produce.
    static func parse(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Prompt-friendly "now", e.g. "Friday, 2026-10-23 19:20 (America/New_York)".
    static func promptNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "EEEE, yyyy-MM-dd HH:mm"
        return "\(f.string(from: .now)) (\(TimeZone.current.identifier))"
    }
}

/// Readable errors thrown from tools.
struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
