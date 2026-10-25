import SwiftUI

/// Plan my day without Apple Intelligence: type the tasks, the Scheduler does the rest.
struct ManualPlanForm: View {
    let initialFocus: FocusPreference
    let onPlan: ([PlanTask], FocusPreference) -> Void
    @State private var tasks = [PlanTask(title: "", minutes: 30)]
    @State private var focus: FocusPreference
    @Environment(\.dismiss) private var dismiss

    init(initialFocus: FocusPreference, onPlan: @escaping ([PlanTask], FocusPreference) -> Void) {
        self.initialFocus = initialFocus
        self.onPlan = onPlan
        _focus = State(initialValue: initialFocus)
    }

    private var ready: [PlanTask] { tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                Section("What must get done today?") {
                    ForEach($tasks) { $task in row($task) }
                    Button { tasks.append(PlanTask(title: "", minutes: 30)) } label: { Label("Add a task", systemImage: "plus") }
                }
                Section("When do you focus best?") {
                    Picker("Focus", selection: $focus) {
                        ForEach(FocusPreference.allCases, id: \.self) { Text($0 == .none ? "No preference" : $0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Plan my day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plan") { onPlan(ready, focus) }.disabled(ready.isEmpty)
                }
            }
        }
    }

    private func row(_ task: Binding<PlanTask>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task", text: task.title)
            Stepper(value: task.minutes, in: 5...480, step: 15) {
                Text(DateText.duration(task.wrappedValue.minutes * 60)).foregroundStyle(.secondary)
            }
            Picker("Priority", selection: task.priority) {
                ForEach(TaskPriority.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Needs deep focus", isOn: task.deep)
            if let due = Binding(task.deadline) {
                DatePicker("Due by", selection: due, displayedComponents: .hourAndMinute)
                Button("Remove deadline", role: .destructive) { task.wrappedValue.deadline = nil }.font(.footnote)
            } else {
                Button("Add a deadline") {
                    task.wrappedValue.deadline = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Hosts the planner's sheets, so the main screen and the unsupported-device screen share them.
struct PlannerSheets: ViewModifier {
    @Bindable var model: TalkViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.showManualPlan) {
                ManualPlanForm(initialFocus: model.planner.focus) { tasks, focus in
                    Task { await model.submitManualPlan(tasks: tasks, focus: focus) }
                }
            }
            .sheet(item: $model.planSession) { session in PlanSheet(model: model, session: session) }
            .sheet(isPresented: $model.showMenu) { MenuHelperView(modelAvailable: model.agent.isModelAvailable) }
    }
}

extension View {
    func plannerSheets(_ model: TalkViewModel) -> some View { modifier(PlannerSheets(model: model)) }
}
