import Foundation
import Observation

enum DayFilter: String, CaseIterable, Identifiable {
    case today = "Today", tomorrow = "Tomorrow", upcoming = "Upcoming"
    var id: String { rawValue }
}

/// The "your day" picture on the home screen. Reads Calendar and Reminders once the user connects them;
/// until then it shows what Sayso itself set up.
@MainActor @Observable
final class DayStore {
    private(set) var items: [AgendaItem] = []
    private(set) var access: AgendaAccess = AgendaReader.access()
    private(set) var briefing: String?
    private var lastBriefedText = ""
    private var refreshCount = 0
    private let life: LifeStore

    init(life: LifeStore) { self.life = life }

    func refresh(agent: AgentService) async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SAYSO_DEMO_DAY"] == "1" { loadDemo(); return }
        #endif
        refreshCount += 1
        let mine = refreshCount
        access = AgendaReader.access()
        if access == .granted {
            let start = Calendar.current.startOfDay(for: .now)
            let loaded = await AgendaReader.load(from: start, to: Calendar.current.date(byAdding: .day, value: 14, to: start)!)
            // A slower, older refresh must not overwrite a newer one (an event added a moment ago would vanish).
            guard mine == refreshCount else { return }
            items = loaded
        } else {
            items = life.agendaItems()
        }
        let text = summaryText()
        guard text != lastBriefedText else { return }
        lastBriefedText = text
        guard !items.isEmpty else { briefing = nil; return }
        briefing = fallbackBriefing()
        if let ai = await agent.briefing(for: text) { briefing = ai }
    }

    func connect(agent: AgentService) async {
        await AgendaReader.connect()
        lastBriefedText = ""
        await refresh(agent: agent)
    }

    func items(for filter: DayFilter) -> [AgendaItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ i: AgendaItem) -> Int? {
            guard let s = i.start else { return nil }
            return cal.dateComponents([.day], from: today, to: cal.startOfDay(for: max(s, today))).day
        }
        let picked: [AgendaItem]
        switch filter {
        case .today: picked = items.filter { day($0) == nil || day($0) == 0 }
        case .tomorrow: picked = items.filter { day($0) == 1 }
        case .upcoming: picked = items.filter { (day($0) ?? 0) >= 2 }
        }
        return picked.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    private func line(_ i: AgendaItem) -> String {
        let time = i.start.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "- \(time) \(i.title)" + (i.detail.isEmpty ? "" : " (\(i.detail))")
    }

    private func summaryText() -> String {
        let today = items(for: .today)
        var s = "Today:\n" + (today.isEmpty ? "- nothing planned" : today.prefix(12).map(line).joined(separator: "\n"))
        let tomorrow = items(for: .tomorrow)
        if !tomorrow.isEmpty { s += "\nTomorrow: \(tomorrow.count) things" }
        return s
    }

    private func fallbackBriefing() -> String {
        let today = items(for: .today)
        guard !today.isEmpty else { return "Nothing planned today." }
        let upcoming = today.first { ($0.start ?? .now) >= .now || $0.kind != .event }
        guard let next = upcoming else { return "You're done for today." }
        let when = next.start.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "\(today.count) on today. Next: \(next.title)\(when)."
    }

    func setDemo(access: AgendaAccess, items: [AgendaItem], briefing: String) {
        self.access = access
        self.items = items
        self.briefing = briefing
    }
}

#if DEBUG
extension DayStore {
    /// Simulator-only sample day for checking the layout.
    fileprivate func loadDemo() {
        let cal = Calendar.current
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: day, to: .now)!)!
        }
        func item(_ id: String, _ k: AgendaItem.Kind, _ t: String, _ d: Date?, _ detail: String = "") -> AgendaItem {
            AgendaItem(id: id, kind: k, title: t, start: d, end: d?.addingTimeInterval(3600), detail: detail, allDay: false)
        }
        setDemo(access: .denied,
                items: [item("1", .event, "Dinner with Ankit", at(0, 23, 50), "Nobu Malibu"),
                        item("2", .reminder, "Book a table", at(0, 23, 55)),
                        item("3", .alarm, "Alarm", at(1, 6, 30), "Weekdays"),
                        item("4", .event, "Flight to Austin", at(1, 14), "SFO"),
                        item("5", .event, "Standup", at(2, 9, 30), "Zoom")],
                briefing: "Dinner with Ankit tonight at 8, and a table still to book.")
    }
}
#endif
