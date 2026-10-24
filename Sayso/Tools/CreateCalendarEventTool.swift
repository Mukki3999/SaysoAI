import FoundationModels

struct CreateCalendarEventTool: Tool {
    let collector: PlanCollector

    let name = "createCalendarEvent"
    let description = "Propose a new calendar event. Use for meetings, appointments, plans and anything with a start time."

    @Generable
    struct Arguments {
        @Guide(description: "Short event title, e.g. 'Lunch with Sam'")
        var title: String
        @Guide(description: "Start in local time, format yyyy-MM-dd'T'HH:mm:ss, resolved from the current date")
        var start: String
        @Guide(description: "End in local time, same format. Omit if the user gave no end or duration")
        var end: String?
        @Guide(description: "Place name or address, only if the user said one")
        var location: String?
        @Guide(description: "Extra notes, only if the user said any")
        var notes: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        guard let start = DateText.parse(a.start) else {
            throw ToolError("I couldn't work out the start time for “\(a.title)”.")
        }
        let end = a.end.flatMap(DateText.parse)
        if let end, end <= start { throw ToolError("The end time for “\(a.title)” is before it starts.") }
        let draft = CalendarEventDraft(title: a.title, start: start, end: end,
                                       location: a.location ?? "", notes: a.notes ?? "")
        let added = await collector.add(.calendar(draft))
        return added ? "Queued calendar event “\(a.title)” for the user to approve." : "Already queued."
    }
}

// MARK: - Execution (only reachable through ActionExecutor with an ApprovedPlan)

import EventKit

enum CalendarEventAction {
    static func perform(_ d: CalendarEventDraft) async throws -> ActionResult.Outcome {
        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted: throw PermissionDenied(feature: "calendar")
        default: break
        }
        // Write-only: Sayso can add events but cannot read the user's calendar.
        guard try await store.requestWriteOnlyAccessToEvents() else { throw PermissionDenied(feature: "calendar") }

        let event = EKEvent(eventStore: store)
        event.title = d.title
        event.startDate = d.start
        event.endDate = d.end ?? d.start.addingTimeInterval(3600)
        if !d.location.isEmpty { event.location = d.location }
        if !d.notes.isEmpty { event.notes = d.notes }
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)

        let box = UnsafeBox((store, event))
        return .completed(undo: {
            try box.value.0.remove(box.value.1, span: .thisEvent)
        })
    }
}
