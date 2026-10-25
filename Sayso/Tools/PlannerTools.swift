import FoundationModels

/// These only record that the user asked for the planner. The planner itself asks its own questions.
struct PlanMyDayTool: Tool {
    let collector: PlanCollector

    let name = "planMyDay"
    let description = "Start planning the user's day around their calendar. Use for 'plan my day', 'organize my day', 'schedule my tasks'."

    @Generable
    struct Arguments {
        @Guide(description: "The user's to-do list for today, in their words, only if they already said it. Otherwise empty")
        var mustDos: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        let text = a.mustDos?.trimmingCharacters(in: .whitespacesAndNewlines)
        await collector.setIntent(.planDay(mustDos: (text?.isEmpty ?? true) ? nil : text))
        return "Planner started. Reply with nothing more."
    }
}

struct RescueMyDayTool: Tool {
    let collector: PlanCollector

    let name = "rescueDay"
    let description = "Re-plan the rest of the user's day because they are running behind. Use for 'I'm 30 minutes behind' and 're-plan the rest of my day'."

    @Generable
    struct Arguments {
        @Guide(description: "How many minutes behind, only if the user said. 'An hour' is 60. Leave empty if they didn't say")
        var minutesBehind: Int?
    }

    func call(arguments a: Arguments) async throws -> String {
        await collector.setIntent(.rescueDay(minutesBehind: a.minutesBehind.map { max($0, 0) }))
        return "Rescue started. Reply with nothing more."
    }
}
