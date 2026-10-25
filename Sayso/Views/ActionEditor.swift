import SwiftUI

/// Edit one proposed action. Changes apply when the user taps Save.
struct ActionEditor: View {
    @State private var draft: ProposedAction
    var onSave: (ProposedAction) -> Void
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(action: ProposedAction, onSave: @escaping (ProposedAction) -> Void, onRemove: @escaping () -> Void) {
        _draft = State(initialValue: action)
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        NavigationStack {
            Form {
                fields
                Section {
                    Button("Remove this action", role: .destructive) { onRemove(); dismiss() }
                }
            }
            .navigationTitle(draft.kindLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(draft); dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var fields: some View {
        switch draft.payload {
        case .calendar(var d):
            Section {
                TextField("Title", text: bind(d.title) { d.title = $0; draft.payload = .calendar(d) })
                DatePicker("Starts", selection: bind(d.start) { d.start = $0; draft.payload = .calendar(d) })
                Toggle("Has end time", isOn: bind(d.end != nil) {
                    d.end = $0 ? d.start.addingTimeInterval(3600) : nil; draft.payload = .calendar(d)
                })
                if let end = d.end {
                    DatePicker("Ends", selection: bind(end) { d.end = $0; draft.payload = .calendar(d) })
                }
                TextField("Location", text: bind(d.location) { d.location = $0; draft.payload = .calendar(d) })
                TextField("Notes", text: bind(d.notes) { d.notes = $0; draft.payload = .calendar(d) }, axis: .vertical)
            }
        case .reminder(var d):
            Section {
                TextField("Title", text: bind(d.title) { d.title = $0; draft.payload = .reminder(d) })
                Toggle("Due date", isOn: bind(d.due != nil) {
                    d.due = $0 ? .now.addingTimeInterval(3600) : nil; draft.payload = .reminder(d)
                })
                if let due = d.due {
                    DatePicker("Due", selection: bind(due) { d.due = $0; draft.payload = .reminder(d) })
                }
                TextField("Place (optional)", text: bind(d.place) { d.place = $0; draft.payload = .reminder(d) })
                if !d.place.isEmpty {
                    Picker("When", selection: bind(d.arriving) { d.arriving = $0; draft.payload = .reminder(d) }) {
                        Text("Arriving").tag(true)
                        Text("Leaving").tag(false)
                    }
                }
            }
        case .alarm(var d):
            Section {
                TextField("Label", text: bind(d.label) { d.label = $0; draft.payload = .alarm(d) })
                DatePicker("Time", selection: bind(Calendar.current.date(from: DateComponents(hour: d.hour, minute: d.minute)) ?? .now) {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    d.hour = c.hour ?? 7; d.minute = c.minute ?? 0; draft.payload = .alarm(d)
                }, displayedComponents: .hourAndMinute)
            }
            Section("Repeat") {
                ForEach(Self.weekdays, id: \.0) { day, name in
                    Toggle(name, isOn: bind(d.repeatDays.contains(day)) {
                        if $0 { d.repeatDays.append(day) } else { d.repeatDays.removeAll { $0 == day } }
                        draft.payload = .alarm(d)
                    })
                }
            }
        case .timer(var d):
            Section {
                TextField("Label", text: bind(d.label) { d.label = $0; draft.payload = .timer(d) })
                Stepper("Minutes: \(d.seconds / 60)", value: bind(d.seconds / 60) {
                    d.seconds = max(1, $0) * 60 + d.seconds % 60; draft.payload = .timer(d)
                }, in: 0...600)
                Stepper("Seconds: \(d.seconds % 60)", value: bind(d.seconds % 60) {
                    d.seconds = max(1, d.seconds / 60 * 60 + $0); draft.payload = .timer(d)
                }, in: 0...59, step: 5)
            }
        case .message(var d):
            Section {
                TextField("To", text: bind(d.recipient) { d.recipient = $0; draft.payload = .message(d) })
                TextField("Message", text: bind(d.body) { d.body = $0; draft.payload = .message(d) }, axis: .vertical)
                    .lineLimit(3...10)
            }
        case .email(var d):
            Section {
                TextField("To", text: bind(d.recipient) { d.recipient = $0; draft.payload = .email(d) })
                TextField("Subject", text: bind(d.subject) { d.subject = $0; draft.payload = .email(d) })
                TextField("Body", text: bind(d.body) { d.body = $0; draft.payload = .email(d) }, axis: .vertical)
                    .lineLimit(4...12)
            }
        case .directions(var d):
            Section {
                TextField("Destination", text: bind(d.destination) { d.destination = $0; draft.payload = .directions(d) })
            }
        case .updateEvent, .deleteEvent:
            EmptyView()   // shown as a diff; changed by asking again
        }
    }

    private static let weekdays: [(Locale.Weekday, String)] = [
        (.monday, "Monday"), (.tuesday, "Tuesday"), (.wednesday, "Wednesday"), (.thursday, "Thursday"),
        (.friday, "Friday"), (.saturday, "Saturday"), (.sunday, "Sunday")
    ]

    private func bind<V>(_ value: V, set: @escaping (V) -> Void) -> Binding<V> {
        // SwiftUI calls these on the main actor; the closures only touch this view's @State.
        nonisolated(unsafe) let value = value
        nonisolated(unsafe) let set = set
        return Binding(get: { value }, set: { set($0) })
    }
}
