import Foundation
import FoundationModels

/// Read-only: looks things up, changes nothing, so it needs no approval step.
struct GetAgendaTool: Tool {
    let name = "getAgenda"
    let description = "Look up what is on the user's calendar, reminders and alarms for one day. Use for questions like 'what's on tomorrow' or 'am I free Saturday'."

    @Generable
    struct Arguments {
        @Guide(description: "The day to look up, format yyyy-MM-dd")
        var day: String
    }

    func call(arguments a: Arguments) async throws -> String {
        guard let date = DateText.parse(a.day) else { throw ToolError("I couldn't tell which day you meant.") }
        guard AgendaReader.access() == .granted else {
            throw ToolError("Sayso can't see your calendar yet. Tap “Show my day” on the home screen to allow it.")
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let items = await AgendaReader.load(from: start, to: end)
        guard !items.isEmpty else { return "Nothing is scheduled on \(a.day)." }
        return items.map { i in
            let time = i.allDay ? "all day" : (i.start.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
            let end = i.end.map { " to " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "\(time)\(end): \(i.title)" + (i.detail.isEmpty ? "" : " (\(i.detail))")
        }.joined(separator: "\n")
    }
}
