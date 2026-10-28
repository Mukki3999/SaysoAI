import SwiftUI

struct ConfirmationSheet: View {
    @Bindable var model: TalkViewModel
    let plan: ActionPlan
    @State private var editing: ProposedAction?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if let results = plan.results { doneHeader(results) } else { reviewHeader }
                ScrollView {
                    VStack(spacing: 14) {
                        if let results = plan.results {
                            ForEach(Array(results.enumerated()), id: \.element.id) { i, r in
                                resultCard(r).staggerIn(i)
                            }
                        } else {
                            ForEach(Array(plan.actions.enumerated()), id: \.element.id) { i, a in
                                if a.isEventChange {
                                    eventChangeCard(a).staggerIn(i)
                                } else {
                                    Button { editing = a } label: { reviewCard(a) }
                                        .buttonStyle(CardPressStyle())
                                        .staggerIn(i)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
                }
                footer
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .presentationCornerRadius(36)
        .interactiveDismissDisabled(plan.isExecuting)
        .sheet(item: $editing) { action in
            ActionEditor(action: action,
                         onSave: { plan.update($0) },
                         onRemove: { plan.remove(action.id); if plan.actions.isEmpty { model.cancel(plan) } })
        }
    }

    // MARK: Headers

    private var reviewHeader: some View {
        VStack(spacing: 8) {
            Text("YOU SAID").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
            Text("“\(plan.transcript)”")
                .font(.title3.weight(.medium)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(3)
            Text(subtitle)
                .font(.footnote).foregroundStyle(.white.opacity(0.5)).padding(.top, 2)
        }
        .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 18)
    }

    private var subtitle: String {
        let changes = plan.actions.filter(\.isEventChange).count
        if changes == plan.actions.count {
            return changes > 1 ? "\(changes) calendar changes · nothing happens until you approve" : "Nothing changes until you approve"
        }
        return plan.actions.count > 1 ? "\(plan.actions.count) things to do · tap a card to edit" : "Tap the card to edit"
    }

    private func doneHeader(_ results: [ActionResult]) -> some View {
        let failed = results.filter { if case .failed = $0.outcome { true } else { false } }.count
        return VStack(spacing: 10) {
            Image(systemName: failed == results.count ? "exclamationmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 44, weight: .light)).foregroundStyle(.white)
                .symbolEffect(.bounce, value: results.count)
            Text(failed == 0 ? "All set" : failed == results.count ? "Couldn't finish" : "Mostly done")
                .font(.title2.weight(.semibold)).foregroundStyle(.white)
        }
        .padding(.top, 38).padding(.bottom, 18)
    }

    // MARK: Cards

    private func reviewCard(_ action: ProposedAction) -> some View {
        ActionCardBody(action: action)
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "pencil").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.4))
                    .frame(width: 30, height: 30).padding(14)
            }
    }

    /// Before/after cards aren't edited by hand: say it differently, or drop the card.
    private func eventChangeCard(_ action: ProposedAction) -> some View {
        VStack(spacing: 0) {
            ActionCardBody(action: action).padding(20)
            if action.editsRepeatingEvent {
                Divider()
                SpanPicker(selection: action.chosenSpan) { plan.setSpan($0, for: action.id) }
                    .padding(.horizontal, 20).padding(.vertical, 14)
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                plan.remove(action.id)
                if plan.actions.isEmpty { model.cancel(plan) }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.5))
                    .frame(width: 30, height: 30).background(Color.black.opacity(0.06), in: Circle())
            }
            .padding(14)
            .accessibilityLabel("Leave this one out")
        }
    }

    private func resultCard(_ r: ActionResult) -> some View {
        VStack(spacing: 0) {
            ActionCardBody(action: r.action).padding(20)
            Divider()
            statusBar(r).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func statusBar(_ r: ActionResult) -> some View {
        HStack(spacing: 10) {
            switch r.outcome {
            case .completed(let undo):
                Label(Self.doneText(r.action), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.black)
                Spacer()
                if undo != nil { pill("Undo") { Task { await model.undo(r.id, in: plan) } } }
            case .ready(let deferred):
                Label(Self.readyText(deferred), systemImage: "arrow.up.forward.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.black)
                Spacer()
                pill(Self.readyButton(deferred)) { model.performDeferred(deferred, resultID: r.id, in: plan) }
            case .failed(let message, let needsSettings):
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote).foregroundStyle(.black.opacity(0.7)).lineLimit(3)
                Spacer(minLength: 8)
                if needsSettings {
                    pill("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8).background(.black, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }

    static func doneText(_ a: ProposedAction) -> String {
        switch a.payload {
        case .calendar: "Added to Calendar"
        case .reminder: "Added to Reminders"
        case .alarm: "Alarm set"
        case .timer: "Timer started"
        case .updateEvent: "Event updated"
        case .deleteEvent: "Event cancelled"
        case .deleteReminder: "Reminder deleted"
        default: "Done"
        }
    }

    static func readyText(_ d: DeferredAction) -> String {
        switch d {
        case .message: "Draft ready"
        case .email: "Draft ready"
        case .directions: "Ready in Maps"
        }
    }

    static func readyButton(_ d: DeferredAction) -> String {
        switch d {
        case .message, .email: "Review & send"
        case .directions: "Open Maps"
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            if plan.results != nil {
                bigButton("Close") { model.reviewing = nil }
            } else {
                if plan.needsSpanChoice {
                    Text("Choose how to apply the repeating event first.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.55))
                }
                bigButton(plan.actions.count > 1 ? "Approve all" : "Approve", busy: plan.isExecuting) {
                    Task { await model.approve(plan) }
                }
                .opacity(plan.needsSpanChoice ? 0.35 : 1)
                .disabled(plan.needsSpanChoice)
                Button("Cancel") { model.cancel(plan) }
                    .font(.body).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 10)
                    .disabled(plan.isExecuting)
            }
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 10)
    }

    private func bigButton(_ title: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy { ProgressView().tint(.black) } else { Text(title) }
            }
            .font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(.white, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
        .disabled(busy)
    }
}
