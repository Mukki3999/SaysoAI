import SwiftUI

/// Before/after review for Plan my day and Rescue my day. Nothing touches the calendar until a button here is tapped.
struct PlanSheet: View {
    @Bindable var model: TalkViewModel
    @Bindable var session: DayPlanSession
    @State private var moving: MoveTarget?
    @State private var busy = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if session.isDayOff && session.items.isEmpty && session.leftovers.isEmpty { dayOffCard } else {
                            timelineCard
                            ForEach(Array(session.items.enumerated()), id: \.element.id) { i, item in
                                itemCard(item).staggerIn(i)
                            }
                            if !session.leftovers.isEmpty { leftoverSection }
                            if session.items.isEmpty && session.leftovers.isEmpty { nothingToChange }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
                footer
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .presentationCornerRadius(36)
        .sheet(item: $moving) { target in
            if let item = session.items.first(where: { $0.id == target.id }) {
                MoveSheet(session: session, item: item)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Text(session.isRescue ? "RESCUE MY DAY" : "PLAN MY DAY")
                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
            Text(headline)
                .font(.system(size: 26, weight: .medium, design: .serif).italic()).foregroundStyle(.white)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12).padding(.top, 30).padding(.bottom, 4)
    }

    private var headline: String {
        if session.isRescue { return "Here's how the rest of today fits." }
        return "Here's a plan for \(session.day.formatted(.dateTime.weekday(.wide)))."
    }

    private var subtitle: String {
        let blocks = session.items.filter { $0.kind != .remove }.count
        if session.isRescue {
            var parts = ["\(session.items.filter { $0.kind == .move }.count) move", "\(session.keptBlocks.count) stay"]
            if !session.leftovers.isEmpty { parts.append("\(session.leftovers.count) don't fit") }
            return parts.joined(separator: " · ") + " · nothing changes until you approve"
        }
        let focus = session.focus == .none ? "" : " · focus: \(session.focus.label.lowercased())"
        return "\(blocks) \(blocks == 1 ? "block" : "blocks")\(focus) · goes in your “\(PlanningCalendar.calendarName)” calendar"
    }

    private var timelineCard: some View {
        DayTimeline(before: session.entries(side: false), after: session.entries(side: true),
                    day: session.day, settings: session.settings)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var dayOffCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today is one of your days off.").font(.headline).foregroundStyle(.black)
            Text("Sayso skips days off. Plan it anyway?").font(.subheadline).foregroundStyle(.black.opacity(0.6))
            pill("Plan anyway", dark: true) { Task { await session.planAnyway() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var nothingToChange: some View {
        Text(session.isRescue ? "Nothing needs to move. You're still on track." : "Nothing to schedule.")
            .font(.subheadline).foregroundStyle(.white.opacity(0.6)).padding(.top, 6)
    }

    // MARK: Block cards

    private func timeText(_ item: PlanItem) -> String {
        let sameDay = Calendar.current.isDate(item.start, inSameDayAs: session.day)
        let range = "\(DateText.clock(item.start)) – \(DateText.clock(item.end))"
        return sameDay ? range : "\(item.start.formatted(.dateTime.weekday(.wide))) · \(range)"
    }

    private func itemCard(_ item: PlanItem) -> some View {
        let dropped = item.status == .dropped
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon(item)).font(.caption.weight(.semibold))
                Text(label(item).uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                Spacer()
            }
            .foregroundStyle(.black.opacity(0.45))

            Text(item.title).font(.title3.weight(.semibold)).foregroundStyle(.black)
                .strikethrough(dropped || item.kind == .remove)

            if item.kind == .move, let os = item.oldStart, let oe = item.oldEnd {
                Text("\(DateText.clock(os)) – \(DateText.clock(oe))").font(.subheadline).foregroundStyle(.black.opacity(0.4)).strikethrough()
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.5))
                    Text(timeText(item)).font(.headline).foregroundStyle(.black)
                }
            } else {
                Text(timeText(item)).font(.subheadline.weight(.medium)).foregroundStyle(.black.opacity(0.75))
            }
            if !item.reason.isEmpty {
                Text(item.reason).font(.footnote.italic()).foregroundStyle(.black.opacity(0.55))
            }
            controls(item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white.opacity(dropped ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func icon(_ item: PlanItem) -> String {
        switch item.kind {
        case .add: "plus.circle"
        case .move: "arrow.right.circle"
        case .remove: "trash"
        }
    }

    private func label(_ item: PlanItem) -> String {
        switch item.kind {
        case .add: "New block"
        case .move: item.reason.hasPrefix("Shortened") ? "Shortened" : "Moved"
        case .remove: "Remove"
        }
    }

    @ViewBuilder
    private func controls(_ item: PlanItem) -> some View {
        switch item.status {
        case .pending:
            HStack(spacing: 8) {
                pill(item.kind == .remove ? "Remove" : "Approve", dark: true) { session.commit(item.id) }
                if item.kind != .remove { pill("Move", dark: false) { moving = MoveTarget(id: item.id) } }
                pill("Drop", dark: false) { session.drop(item.id) }
            }
            if let err = item.moveError { Text(err).font(.footnote).foregroundStyle(.black.opacity(0.6)) }
        case .committed:
            HStack {
                Label(item.kind == .remove ? "Removed" : "In your calendar", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.black)
                Spacer()
                if item.undo != nil { pill("Undo", dark: true) { Task { await session.undo(item.id) } } }
            }
        case .dropped:
            HStack {
                Text("Left out").font(.subheadline).foregroundStyle(.black.opacity(0.5))
                Spacer()
                pill("Restore", dark: false) { session.restore(item.id) }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(.black.opacity(0.7))
        }
    }

    // MARK: Things that don't fit

    private var leftoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOESN'T FIT").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
            ForEach(session.leftovers) { state in leftoverCard(state) }
        }
        .padding(.top, 6)
    }

    private func leftoverCard(_ state: LeftoverState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.leftover.task.title).font(.title3.weight(.semibold)).foregroundStyle(.black)
            Text("\(DateText.duration(state.leftover.task.minutes * 60)) · \(state.leftover.reason)")
                .font(.footnote).foregroundStyle(.black.opacity(0.6))
            switch state.choice {
            case .undecided:
                HStack(spacing: 8) {
                    pill("Tomorrow", dark: true) { Task { await session.resolve(state.id, .tomorrow(.now)) } }
                    if let n = state.leftover.shortenTo, n >= 15 {
                        pill("Shorten to \(n) min", dark: false) { Task { await session.resolve(state.id, .shortened(n)) } }
                    }
                    pill("Drop", dark: false) { Task { await session.resolve(state.id, .dropped) } }
                }
                if session.isRescue {
                    Text("Until you choose, its old slot stays on your calendar.").font(.caption).foregroundStyle(.black.opacity(0.45))
                }
            case .tomorrow(let d):
                Label("Moved to \(d.formatted(.dateTime.weekday(.wide)))", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.black)
            case .shortened(let n):
                Label("Shortened to \(n) min", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.black)
            case .dropped:
                Label("Dropped", systemImage: "xmark.circle.fill").font(.subheadline.weight(.medium)).foregroundStyle(.black.opacity(0.6))
            }
            if let note = state.note { Text(note).font(.footnote).foregroundStyle(.black.opacity(0.6)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 4) {
            if session.pendingCount > 0 {
                bigButton("Approve all (\(session.pendingCount))") { session.commitAll() }
                Button("Cancel") { model.closePlanSession() }
                    .font(.body).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 10)
            } else {
                bigButton(session.committedCount > 0 ? "Done" : "Close") { model.closePlanSession() }
                if session.committedCount > 1 {
                    Button("Undo all") { Task { await session.undoAll() } }
                        .font(.body).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 10)
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 17).background(.white, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }

    private func pill(_ title: String, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(dark ? .white : .black)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(dark ? Color.black : Color.black.opacity(0.07), in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }
}

struct MoveTarget: Identifiable { let id: UUID }

/// Picks a new start time for one block. Refuses times that collide with an event, lunch, or another block.
struct MoveSheet: View {
    let session: DayPlanSession
    let item: PlanItem
    @State private var start: Date
    @Environment(\.dismiss) private var dismiss

    init(session: DayPlanSession, item: PlanItem) {
        self.session = session
        self.item = item
        _start = State(initialValue: item.start)
    }

    private var conflict: String? { session.conflict(for: item.id, startingAt: start) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(item.title).font(.headline)
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden()
                Text(conflict ?? "Ends at \(DateText.clock(start.addingTimeInterval(item.end.timeIntervalSince(item.start))))")
                    .font(.footnote).foregroundStyle(conflict == nil ? Color.secondary : Color.red)
                Spacer()
            }
            .padding()
            .navigationTitle("Move block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { session.move(item.id, to: start); dismiss() }.disabled(conflict != nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
