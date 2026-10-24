import SwiftUI

struct ConfirmationSheet: View {
    @Bindable var model: TalkViewModel
    let plan: ActionPlan
    @State private var editing: ProposedAction?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            if let results = model.results {
                doneContent(results)
            } else {
                reviewContent
            }
        }
        .padding(.top, 24)
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isExecuting)
        .sheet(item: $editing) { action in
            ActionEditor(action: action,
                         onSave: { plan.update($0) },
                         onRemove: { plan.remove(action.id); if plan.actions.isEmpty { model.cancelPlan() } })
        }
    }

    // MARK: Review

    private var reviewContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Here's what I'll do").font(.title3.weight(.semibold))
                Text("“\(plan.transcript)”").font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(plan.actions) { action in
                        Button { editing = action } label: { card(action) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            VStack(spacing: 10) {
                Button { Task { await model.approve() } } label: {
                    Group {
                        if model.isExecuting { ProgressView().tint(Color(.systemBackground)) }
                        else { Text(plan.actions.count > 1 ? "Approve all" : "Approve") }
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent).tint(.primary)
                .foregroundStyle(Color(.systemBackground))
                .clipShape(Capsule())
                .disabled(model.isExecuting)

                Button("Cancel", role: .cancel) { model.cancelPlan() }
                    .foregroundStyle(.secondary)
                    .disabled(model.isExecuting)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }

    private func card(_ action: ProposedAction) -> some View {
        HStack(spacing: 14) {
            Image(systemName: action.symbol).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.kindLabel).font(.caption).foregroundStyle(.secondary)
                Text(action.summary).font(.body).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: Done

    private func doneContent(_ results: [ActionResult]) -> some View {
        VStack(spacing: 16) {
            Text("Done").font(.title3.weight(.semibold))
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(results) { result in resultRow(result) }
                }
                .padding(.horizontal, 20)
            }
            Button("Close") { model.closePlan() }
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }

    private func resultRow(_ result: ActionResult) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(for: result)).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.body)
                if case .failed(let message, _) = result.outcome {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            rowAction(result)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func icon(for result: ActionResult) -> String {
        switch result.outcome {
        case .completed: "checkmark.circle"
        case .ready: result.symbol
        case .failed: "exclamationmark.circle"
        }
    }

    @ViewBuilder
    private func rowAction(_ result: ActionResult) -> some View {
        switch result.outcome {
        case .completed(let undo):
            if undo != nil {
                Button("Undo") { Task { await model.undo(result.id) } }.buttonStyle(.bordered).tint(.primary)
            }
        case .ready(let deferred):
            Button(deferredLabel(deferred)) { model.performDeferred(deferred, resultID: result.id) }
                .buttonStyle(.bordered).tint(.primary)
        case .failed(_, let needsSettings):
            if needsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.buttonStyle(.bordered).tint(.primary)
            }
        }
    }

    private func deferredLabel(_ d: DeferredAction) -> String {
        switch d {
        case .message, .email: "Review & send"
        case .directions: "Open Maps"
        }
    }
}
