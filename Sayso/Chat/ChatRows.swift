import SwiftUI

/// One entry in the thread. Plain text for conversation, white cards for anything you act on.
struct MessageRow: View {
    @Bindable var model: TalkViewModel
    let message: ChatMessage

    var body: some View {
        switch (message.role, message.content) {
        case (.user, .text(let text)):
            UserBubble { Text(text).font(.body).foregroundStyle(.white) }
        case (.user, .photo(let image, let caption)):
            UserBubble {
                VStack(alignment: .trailing, spacing: 8) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 190, height: 150).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if !caption.isEmpty { Text(caption).font(.body).foregroundStyle(.white) }
                }
            }
        case (_, .text(let text)):
            AssistantText(text: text, choices: message.choices) { model.choose($0) }
        case (_, .proposal(let plan)):
            ProposalCard(model: model, plan: plan)
        case (_, .agenda(let title, let items)):
            AgendaListCard(title: title, items: items)
        case (_, .planCard(let session)):
            PlanCard(model: model, session: session)
        case (_, .error(let text, let needsSettings)):
            ErrorRow(model: model, text: text, needsSettings: needsSettings)
        default:
            EmptyView()
        }
    }
}

struct UserBubble<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack {
            Spacer(minLength: 56)
            content
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

struct AssistantText: View {
    let text: String
    let choices: [Choice]
    let onChoose: (Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 26, height: 26).background(.white, in: Circle()).padding(.top, 1)
                Text(text).font(.system(size: 17)).foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 24)
            }
            if !choices.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(choices) { c in
                            Button { onChoose(c) } label: {
                                Text(c.label).font(.footnote.weight(.semibold)).foregroundStyle(.black)
                                    .padding(.horizontal, 14).padding(.vertical, 9).background(.white, in: Capsule())
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden).padding(.leading, 36)
            }
        }
    }
}

struct ErrorRow: View {
    @Bindable var model: TalkViewModel
    let text: String
    let needsSettings: Bool
    @Environment(\.openURL) private var openURL
    @State private var showDetails = false

    /// Friendly line, then (optionally) the technical detail after a line break.
    private var parts: (main: String, detail: String?) {
        let pieces = text.split(separator: "\n", maxSplits: 1).map(String.init)
        return (pieces.first ?? text, pieces.count > 1 ? pieces[1] : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 26, height: 26).background(Color.white.opacity(0.7), in: Circle())
                Text(parts.main).font(.system(size: 16)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 24)
            }
            HStack(spacing: 8) {
                if needsSettings {
                    pill("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                } else {
                    pill("Try again") { model.retry() }
                    pill("Edit") { model.editLast() }
                    if parts.detail != nil {
                        Button(showDetails ? "Hide details" : "Details") { withAnimation(.smooth) { showDetails.toggle() } }
                            .font(.footnote).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.leading, 36)
            if showDetails, let detail = parts.detail {
                Text(detail).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4)).textSelection(.enabled).padding(.leading, 36)
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.black)
                .padding(.horizontal, 14).padding(.vertical, 9).background(.white, in: Capsule())
        }
    }
}

/// While the model works: a verb that changes every couple of seconds, shimmering, and a way out.
struct ThinkingRow: View {
    let status: String
    let onCancel: () -> Void

    private static let verbs = [
        "Pondering", "Untangling", "Percolating", "Noodling", "Conjuring", "Choreographing", "Cogitating",
        "Marinating", "Wrangling", "Ruminating", "Concocting", "Deciphering", "Tinkering", "Mulling it over",
        "Connecting the dots", "Rearranging the furniture", "Consulting the stars", "Herding your calendar"
    ]
    @State private var start = Int.random(in: 0..<verbs.count)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                .frame(width: 26, height: 26).background(.white, in: Circle()).symbolEffect(.pulse)
            if status == "Thinking…" {
                TimelineView(.periodic(from: .now, by: 2.2)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate / 2.2)
                    Shimmer(text: Self.verbs[(start + tick) % Self.verbs.count] + "…")
                        .id(tick)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.4), value: start)
            } else {
                Shimmer(text: status)
            }
            Spacer()
            Button("Cancel", action: onCancel).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Grey text with a soft highlight sweeping across it.
struct Shimmer: View {
    let text: String
    @State private var phase: CGFloat = -0.4

    var body: some View {
        Text(text).font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))
            .overlay {
                Text(text).font(.system(size: 16)).foregroundStyle(.white)
                    .mask {
                        GeometryReader { g in
                            LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: g.size.width * 0.5)
                                .offset(x: g.size.width * phase)
                        }
                    }
            }
            .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

/// What the user is saying right now, shown as it is transcribed.
struct ListeningRow: View {
    let transcript: String
    var body: some View {
        UserBubble {
            Text(transcript.isEmpty ? "Listening…" : transcript)
                .font(.body.italic()).foregroundStyle(.white.opacity(transcript.isEmpty ? 0.5 : 1))
        }
    }
}

// MARK: - Proposal (the things Sayso is about to do, or did)

struct ProposalCard: View {
    @Bindable var model: TalkViewModel
    let plan: ActionPlan
    @Environment(\.openURL) private var openURL

    private var inactive: Bool { plan.status == .cancelled || plan.status == .replaced }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)
            if let results = plan.results, plan.status == .done {
                ForEach(results) { r in resultRow(r) }
            } else {
                ForEach(plan.actions) { a in actionRow(a) }
            }
            footer.padding(.horizontal, 18).padding(.vertical, 14)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .opacity(inactive ? 0.45 : 1)
        .animation(.smooth, value: plan.status)
    }

    private var header: some View {
        HStack {
            Text(headerText).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.black.opacity(0.45))
            Spacer()
        }
    }

    private var headerText: String {
        switch plan.status {
        case .pending: plan.actions.count > 1 ? "\(plan.actions.count) THINGS TO DO" : "READY TO DO"
        case .done: "DONE"
        case .cancelled: "CANCELLED"
        case .replaced: "REPLACED BY A NEWER REQUEST"
        }
    }

    private func actionRow(_ a: ProposedAction) -> some View {
        HStack(spacing: 14) {
            icon(a.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.kindLabel.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.black.opacity(0.4))
                Text(a.summary).font(.system(size: 16, weight: .medium)).foregroundStyle(.black).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func resultRow(_ r: ActionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                icon(r.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.action.kindLabel.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.black.opacity(0.4))
                    Text(r.action.summary).font(.system(size: 16, weight: .medium)).foregroundStyle(.black).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            status(r).padding(.leading, 50)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    @ViewBuilder
    private func status(_ r: ActionResult) -> some View {
        switch r.outcome {
        case .completed(let undo):
            HStack {
                Label(ConfirmationSheet.doneText(r.action), systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(.black)
                Spacer()
                if undo != nil { pill("Undo") { Task { await model.undo(r.id, in: plan) } } }
            }
        case .ready(let deferred):
            HStack {
                Label(ConfirmationSheet.readyText(deferred), systemImage: "arrow.up.forward.circle")
                    .font(.footnote.weight(.medium)).foregroundStyle(.black)
                Spacer()
                pill(ConfirmationSheet.readyButton(deferred)) { model.performDeferred(deferred, resultID: r.id, in: plan) }
            }
        case .failed(let message, let needsSettings):
            HStack(alignment: .top) {
                Label(message, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(.black.opacity(0.7))
                Spacer(minLength: 8)
                if needsSettings {
                    pill("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if plan.status == .pending {
            VStack(spacing: 10) {
                if plan.needsSpanChoice {
                    Text("This changes a repeating event. Review to choose how.").font(.footnote).foregroundStyle(.black.opacity(0.55))
                }
                HStack(spacing: 8) {
                    Button {
                        if plan.needsSpanChoice { model.reviewing = plan } else { Task { await model.approve(plan) } }
                    } label: {
                        Group {
                            if plan.isExecuting { ProgressView().tint(.white) }
                            else { Text(plan.needsSpanChoice ? "Review" : plan.actions.count > 1 ? "Approve all" : "Approve") }
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13).background(.black, in: Capsule())
                    }
                    .buttonStyle(CardPressStyle()).disabled(plan.isExecuting)
                    if !plan.needsSpanChoice {
                        Button { model.reviewing = plan } label: {
                            Text("Details").font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 18).padding(.vertical, 13).background(Color.black.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(CardPressStyle())
                    }
                    Button { model.cancel(plan) } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.black.opacity(0.6))
                            .frame(width: 46, height: 46).background(Color.black.opacity(0.07), in: Circle())
                    }
                    .accessibilityLabel("Cancel")
                    .disabled(plan.isExecuting)
                }
            }
        }
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 36, height: 36).background(.black, in: Circle())
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7).background(.black, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }
}

// MARK: - Day plan

struct PlanCard: View {
    @Bindable var model: TalkViewModel
    let session: DayPlanSession

    var body: some View {
        let blocks = session.items.filter { $0.kind != .remove }.count
        VStack(alignment: .leading, spacing: 10) {
            Text(session.isRescue ? "RESCUE MY DAY" : "PLAN MY DAY")
                .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.black.opacity(0.45))
            Text(session.isRescue
                 ? "\(session.items.count) \(session.items.count == 1 ? "block moves" : "blocks move"), \(session.keptBlocks.count) stay"
                 : "\(blocks) \(blocks == 1 ? "block" : "blocks") for \(session.day.formatted(.dateTime.weekday(.wide)))")
                .font(.title3.weight(.semibold)).foregroundStyle(.black)
            if !session.leftovers.isEmpty {
                Text("\(session.leftovers.count) didn't fit").font(.subheadline).foregroundStyle(.black.opacity(0.6))
            }
            Text("Nothing is added until you approve it.").font(.footnote).foregroundStyle(.black.opacity(0.5))
            Button { model.planSession = session } label: {
                Text("Review").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).background(.black, in: Capsule())
            }
            .buttonStyle(CardPressStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - Agenda list (an answer to "what's on tomorrow?")

struct AgendaListCard: View {
    let title: String
    let items: [AgendaItem]
    @State private var expanded = false

    private var shown: [AgendaItem] { expanded ? items : Array(items.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.black.opacity(0.45))
                Spacer()
                Text("\(items.count) \(items.count == 1 ? "thing" : "things")").font(.caption).foregroundStyle(.black.opacity(0.45))
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
            ForEach(shown) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(time(item)).font(.subheadline.monospacedDigit().weight(.medium)).foregroundStyle(.black.opacity(0.5))
                        .frame(width: 74, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.kind == .alarm && item.start != nil ? "Alarm" : item.title)
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(.black).fixedSize(horizontal: false, vertical: true)
                        if item.kind == .event, !item.detail.isEmpty {
                            Text(item.detail).font(.footnote).foregroundStyle(.black.opacity(0.5)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
            }
            if items.count > 6 {
                Button { withAnimation(.smooth) { expanded.toggle() } } label: {
                    Text(expanded ? "Show less" : "Show \(items.count - 6) more").font(.footnote.weight(.semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            Color.clear.frame(height: 8)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func time(_ i: AgendaItem) -> String {
        if i.allDay { return "All day" }
        return i.start.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Now"
    }
}
