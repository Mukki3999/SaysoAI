import SwiftUI

/// One thing in the user's day, drawn as a white card on the dark home screen.
/// The next item is "featured": bigger, stacked, and with a map when it has a place.
struct AgendaCard: View {
    let item: AgendaItem
    var featured = false
    var stacked = false
    /// Set for Calendar events: shows a ⋯ button that starts a delete.
    var onDelete: (() -> Void)? = nil

    private var isClockAlarm: Bool { item.kind == .alarm && item.start != nil }

    private var kindLabel: String {
        switch item.kind {
        case .event: "Event"
        case .reminder: "Reminder"
        case .alarm: item.start == nil ? "Timer" : "Alarm"
        }
    }

    private var symbol: String {
        switch item.kind {
        case .event: "calendar"
        case .reminder: "checklist"
        case .alarm: item.start == nil ? "timer" : "alarm"
        }
    }

    private var title: String {
        if isClockAlarm, let s = item.start { return s.formatted(date: .omitted, time: .shortened) }
        return item.title
    }

    private var subtitle: String {
        switch item.kind {
        case .event: ""
        case .reminder, .alarm: item.detail
        }
    }

    private var timeChip: String? {
        guard let start = item.start else { return nil }
        if item.kind == .alarm { return nil }
        if item.allDay { return item.kind == .reminder ? "Due today" : "All day" }
        let from = start.formatted(date: .omitted, time: .shortened)
        if let end = item.end, item.kind == .event { return "\(from) – \(end.formatted(date: .omitted, time: .shortened))" }
        return from
    }

    private var statusChip: (String, String)? {
        guard let start = item.start else { return ("hourglass", "Running") }
        if item.allDay { return nil }
        if item.kind == .event, let end = item.end {
            if start <= .now, end > .now { return ("dot.radiowaves.left.and.right", "Ongoing") }
            if end <= .now { return ("checkmark", "Done") }
        }
        if start > .now {
            return ("arrow.right", start.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        return item.kind == .reminder ? ("exclamationmark", "Overdue") : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.semibold))
                Text(kindLabel).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.black.opacity(0.7))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.black.opacity(0.06), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                            .frame(width: 44, height: 34).background(Color.black.opacity(0.06), in: Capsule())
                    }
                    .accessibilityLabel("Delete \(item.title)")
                }
            }

            Text(title)
                .font(.system(size: featured ? 30 : 23, weight: .regular))
                .foregroundStyle(.black)
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.black.opacity(0.55)).lineLimit(1)
            }

            HStack(spacing: 8) {
                if let t = timeChip { Chip(symbol: "clock", text: t) }
                if let (icon, text) = statusChip { Chip(symbol: icon, text: text) }
                if item.kind == .event, !item.detail.isEmpty, !(featured) {
                    Chip(symbol: "mappin.and.ellipse", text: item.detail)
                }
            }
            .lineLimit(1)

            if featured, item.kind == .event, !item.detail.isEmpty {
                DirectionsPreview(d: DirectionsDraft(destination: item.detail), caption: "Tap to get directions")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(alignment: .top) {
            if stacked {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white.opacity(0.28))
                        .padding(.horizontal, 34).offset(y: -20)
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white.opacity(0.55))
                        .padding(.horizontal, 17).offset(y: -10)
                }
            }
        }
        .opacity(item.kind == .event && (item.end ?? .distantFuture) < .now ? 0.55 : 1)
    }
}
