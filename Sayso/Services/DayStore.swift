import Foundation
import Observation

struct DaySection: Identifiable {
    let title: String
    let items: [AgendaItem]
    var id: String { title }
}

/// The "your day" picture on the home screen, rebuilt from the system apps each time it's shown.
@MainActor @Observable
final class DayStore {
    private(set) var items: [AgendaItem] = []
    private(set) var access: AgendaAccess = AgendaReader.access()
    private(set) var briefing: String?
    private var lastBriefedText = ""

    func refresh(agent: AgentService) async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SAYSO_DEMO_DAY"] == "1" { loadDemo(); return }
        #endif
        access = AgendaReader.access()
        guard access == .granted else { items = []; briefing = nil; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 3, to: start)!
        items = await AgendaReader.load(from: start, to: end)

        let text = summaryText()
        guard text != lastBriefedText else { return }
        lastBriefedText = text
        briefing = fallbackBriefing()
        if let ai = await agent.briefing(for: text) { briefing = ai }
    }

    func setDemo(access: AgendaAccess, items: [AgendaItem], briefing: String) {
        self.access = access
        self.items = items
        self.briefing = briefing
    }

    func connect(agent: AgentService) async {
        await AgendaReader.connect()
        await refresh(agent: agent)
    }

    var sections: [DaySection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var buckets: [Date: [AgendaItem]] = [:]
        var running: [AgendaItem] = []
        for item in items {
            if let s = item.start { buckets[cal.startOfDay(for: max(s, today)), default: []].append(item) }
            else { running.append(item) }
        }
        var out: [DaySection] = []
        if !running.isEmpty { out.append(DaySection(title: "Running", items: running)) }
        for offset in 0..<3 {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let list = (buckets[day] ?? []).sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
            guard offset == 0 || !list.isEmpty else { continue }
            let title = offset == 0 ? "Today" : offset == 1 ? "Tomorrow"
                : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            out.append(DaySection(title: title, items: list))
        }
        return out
    }

    private func todayItems() -> [AgendaItem] { sections.first { $0.title == "Today" }?.items ?? [] }

    private func line(_ i: AgendaItem) -> String {
        let time = i.start.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "- \(time) \(i.title)" + (i.detail.isEmpty ? "" : " (\(i.detail))")
    }

    private func summaryText() -> String {
        var s = "Today:\n" + (todayItems().isEmpty ? "- nothing planned" : todayItems().prefix(12).map(line).joined(separator: "\n"))
        if let tomorrow = sections.first(where: { $0.title == "Tomorrow" }) {
            s += "\nTomorrow: \(tomorrow.items.count) things"
        }
        return s
    }

    private func fallbackBriefing() -> String {
        let today = todayItems().filter { ($0.start ?? .now) >= .now || $0.kind == .reminder }
        guard let next = today.first else { return todayItems().isEmpty ? "Nothing planned today." : "You're done for today." }
        let when = next.start.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "\(todayItems().count) on today. Next: \(next.title)\(when)."
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
        setDemo(access: .granted,
                items: [item("1", .event, "Standup", at(0, 9, 30), "Zoom"),
                        item("2", .reminder, "Call mom", at(0, 18)),
                        item("3", .event, "Dinner with Ankit", at(0, 20), "Nobu"),
                        item("4", .alarm, "Alarm", at(1, 6, 30), "Weekdays"),
                        item("5", .event, "Flight to Austin", at(1, 14))],
                briefing: "Light day: standup at 9:30, then dinner with Ankit at 8.")
    }
}
#endif
