import EventKit
import FoundationModels
import MapKit

struct CreateReminderTool: Tool {
    let collector: PlanCollector

    let name = "createReminder"
    let description = "Propose a reminder or to-do. Use for 'remind me to…'. Can be due at a time and/or when arriving at or leaving a place."

    @Generable
    enum Trigger: String {
        case arriving, leaving
    }

    @Generable
    struct LocationTrigger {
        @Guide(description: "Place name or address, e.g. 'the grocery store' or 'home'")
        var place: String
        var when: Trigger
    }

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded of, e.g. 'Call mom'")
        var title: String
        @Guide(description: "Due time in local time, format yyyy-MM-dd'T'HH:mm:ss. Omit if no time was given")
        var due: String?
        @Guide(description: "Only if the user wants the reminder at a place")
        var locationTrigger: LocationTrigger?
    }

    func call(arguments a: Arguments) async throws -> String {
        var due: Date?
        if let raw = a.due {
            guard let parsed = DateText.parse(raw) else { throw ToolError("I couldn't work out when to remind you about “\(a.title)”.") }
            due = parsed
        }
        let draft = ReminderDraft(title: a.title, due: due,
                                  place: a.locationTrigger?.place ?? "",
                                  arriving: a.locationTrigger?.when != .leaving)
        let added = await collector.add(.reminder(draft))
        return added ? "Queued reminder “\(a.title)” for the user to approve." : "Already queued."
    }
}

// MARK: - Execution (only reachable through ActionExecutor with an ApprovedPlan)

enum ReminderAction {
    static func perform(_ d: ReminderDraft) async throws -> ActionResult.Outcome {
        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .denied, .restricted: throw PermissionDenied(feature: "reminders")
        default: break
        }
        guard try await store.requestFullAccessToReminders() else { throw PermissionDenied(feature: "reminders") }
        guard let list = store.defaultCalendarForNewReminders() else { throw ToolError("No reminders list is available.") }

        let reminder = EKReminder(eventStore: store)
        reminder.title = d.title
        reminder.calendar = list
        if let due = d.due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        if !d.place.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = d.place
            let item = try await MKLocalSearch(request: request).start().mapItems.first
            guard let location = item?.location else { throw ToolError("I couldn't find “\(d.place)” on the map.") }
            let structured = EKStructuredLocation(title: item?.name ?? d.place)
            structured.geoLocation = location
            structured.radius = 150
            let alarm = EKAlarm()
            alarm.structuredLocation = structured
            alarm.proximity = d.arriving ? .enter : .leave
            reminder.addAlarm(alarm)
        }
        try store.save(reminder, commit: true)

        let box = UnsafeBox((store, reminder))
        return .completed(undo: {
            try box.value.0.remove(box.value.1, commit: true)
        })
    }
}
