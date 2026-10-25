import EventKit
import SwiftUI

struct SettingsSheet: View {
    @Bindable var planner: PlannerSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmRemove = false
    @State private var removeMessage: String?
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)

    // TODO before submission: replace with your real URLs.
    private let privacyURL = URL(string: "https://example.com/sayso/privacy")!
    private let supportURL = URL(string: "https://example.com/sayso/support")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private static let days: [(Int, String)] = [(2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"),
                                                (6, "Friday"), (7, "Saturday"), (1, "Sunday")]
    private static let buffers = [0, 5, 10, 15, 20, 30]

    var body: some View {
        NavigationStack {
            List {
                Section("Working hours") {
                    DatePicker("Start", selection: time(\.workStart), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: time(\.workEnd), displayedComponents: .hourAndMinute)
                    Picker("Buffer between blocks", selection: $planner.plan.buffer) {
                        ForEach(Self.buffers, id: \.self) { Text($0 == 0 ? "None" : "\($0) min").tag($0) }
                    }
                    Picker("Best focus time", selection: $planner.focus) {
                        ForEach(FocusPreference.allCases, id: \.self) { Text($0 == .none ? "No preference" : $0.label).tag($0) }
                    }
                }
                Section("Lunch") {
                    Toggle("Protect lunch", isOn: $planner.plan.lunchProtected)
                    if planner.plan.lunchProtected {
                        DatePicker("From", selection: time(\.lunchStart), displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: time(\.lunchEnd), displayedComponents: .hourAndMinute)
                    }
                }
                Section("Days off") {
                    ForEach(Self.days, id: \.0) { number, name in
                        Toggle(name, isOn: dayOff(number))
                    }
                }
                Section {
                    if calendarStatus != .fullAccess {
                        Button(calendarStatus == .denied ? "Open Settings to allow calendar access" : "Allow full calendar access") {
                            Task { await allowCalendar() }
                        }
                    }
                    Button("Remove “\(PlanningCalendar.calendarName)” calendar", role: .destructive) { confirmRemove = true }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Planning, editing and cancelling events need full calendar access. Everything Sayso plans goes in its own “\(PlanningCalendar.calendarName)” calendar, so you can remove it all in one step.")
                }
                Section("Troubleshooting") {
                    NavigationLink("Run self-test") { DiagnosticsView() }
                }
                Section {
                    Link("Privacy policy", destination: privacyURL)
                    Link("Support", destination: supportURL)
                }
                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Sayso runs on your iPhone. Your voice and requests never leave it.")
                }
            }
            .navigationTitle("Sayso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove the “\(PlanningCalendar.calendarName)” calendar?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove calendar and everything in it", role: .destructive) { removePlan() }
            } message: {
                Text("This deletes every block Sayso planned. Your other calendars aren't touched.")
            }
            .alert(removeMessage ?? "", isPresented: Binding(get: { removeMessage != nil }, set: { if !$0 { removeMessage = nil } })) {
                Button("OK") {}
            }
        }
        .presentationDetents([.large])
    }

    private func allowCalendar() async {
        if calendarStatus == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }
        try? await CalendarAccess.ensureFullEvents()
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func removePlan() {
        do {
            let calendar = PlanningCalendar()
            guard calendar.existingPlanCalendar() != nil else {
                removeMessage = "There's no “\(PlanningCalendar.calendarName)” calendar to remove."
                return
            }
            try calendar.removePlanCalendar()
            removeMessage = "Removed. Everything Sayso planned is gone."
        } catch {
            removeMessage = "Couldn't remove it: \(error.localizedDescription)"
        }
    }

    /// Minutes-from-midnight settings shown as time pickers.
    private func time(_ keyPath: WritableKeyPath<PlanSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = planner.plan[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                planner.plan[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private func dayOff(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { planner.plan.daysOff.contains(weekday) },
            set: { on in
                if on { planner.plan.daysOff.insert(weekday) } else { planner.plan.daysOff.remove(weekday) }
            })
    }
}
