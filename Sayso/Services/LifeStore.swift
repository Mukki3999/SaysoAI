import Foundation
import Observation

/// Remembers what Sayso set up, so the home screen shows it even before the user connects their calendar.
@MainActor @Observable
final class LifeStore {
    struct Entry: Codable, Identifiable {
        let action: ProposedAction
        let createdAt: Date
        var id: UUID { action.id }
    }

    private(set) var entries: [Entry] = []
    private let key = "sayso.life.entries"

    init() { load() }

    func add(_ actions: [ProposedAction]) {
        let keep = actions.filter {
            switch $0.payload {
            case .calendar, .reminder, .alarm, .timer: true
            default: false
            }
        }
        guard !keep.isEmpty else { return }
        entries += keep.map { Entry(action: $0, createdAt: .now) }
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// What's still relevant today or later, as home-screen items.
    func agendaItems() -> [AgendaItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var out: [AgendaItem] = []
        for e in entries {
            switch e.action.payload {
            case .calendar(let d):
                let end = d.end ?? d.start.addingTimeInterval(3600)
                guard end >= today else { continue }
                out.append(AgendaItem(id: "l-\(e.id)", kind: .event, title: d.title, start: d.start, end: end,
                                      detail: d.location, allDay: false))
            case .reminder(let d):
                let when = d.due ?? today
                guard when >= today else { continue }
                out.append(AgendaItem(id: "l-\(e.id)", kind: .reminder, title: d.title, start: when, end: nil,
                                      detail: d.place.isEmpty ? "" : "\(d.arriving ? "Arriving" : "Leaving") \(d.place)",
                                      allDay: d.due == nil))
            case .alarm(let d):
                let anchor: Date = d.repeatDays.isEmpty ? e.createdAt : .now
                guard let fire = AgendaReader.nextFire(hour: d.hour, minute: d.minute, days: d.repeatDays, after: anchor),
                      fire >= .now else { continue }
                var detail = d.repeatDays.isEmpty ? "" : DateText.days(d.repeatDays)
                if !d.label.isEmpty { detail = detail.isEmpty ? d.label : "\(d.label) · \(detail)" }
                out.append(AgendaItem(id: "l-\(e.id)", kind: .alarm, title: "Alarm", start: fire, end: nil,
                                      detail: detail, allDay: false))
            case .timer(let d):
                let ends = e.createdAt.addingTimeInterval(TimeInterval(d.seconds))
                guard ends > .now else { continue }
                let label = d.label.isEmpty ? "Timer" : d.label
                out.append(AgendaItem(id: "l-\(e.id)", kind: .alarm, title: label, start: nil, end: ends,
                                      detail: "Ends \(ends.formatted(date: .omitted, time: .shortened))", allDay: false))
            default: break
            }
        }
        return out
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        // Keep a week of history so the list doesn't grow forever.
        entries = decoded.filter { $0.createdAt > Date.now.addingTimeInterval(-7 * 86400) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}
