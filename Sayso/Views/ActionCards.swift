import MapKit
import SwiftUI

/// What each task will actually do, drawn as the thing it creates. Shared by review and done states.
struct ActionCardBody: View {
    let action: ProposedAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: action.symbol).font(.caption.weight(.semibold))
                Text(action.kindLabel.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                Spacer()
            }
            .foregroundStyle(.black.opacity(0.45))
            preview
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch action.payload {
        case .calendar(let d): CalendarPreview(d: d)
        case .reminder(let d): ReminderPreview(d: d)
        case .alarm(let d): AlarmPreview(d: d)
        case .timer(let d): TimerPreview(d: d)
        case .message(let d): MessagePreview(d: d)
        case .email(let d): EmailPreview(d: d)
        case .directions(let d): DirectionsPreview(d: d)
        case .updateEvent(let d): EventDiffPreview(before: d.before, after: d.after, removing: false)
        case .deleteEvent(let d): EventDiffPreview(before: d.before, after: nil, removing: true)
        case .deleteReminder(let d):
            HStack(spacing: 10) {
                Image(systemName: "checklist").foregroundStyle(.black.opacity(0.5))
                Text(d.title).strikethrough().foregroundStyle(.black.opacity(0.6)).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(14).background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Pieces

struct Chip: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.black.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.06), in: Capsule())
    }
}

private struct CalendarPreview: View {
    let d: CalendarEventDraft

    private var timeLine: String {
        var s = d.start.formatted(.dateTime.weekday(.wide)) + " · " + d.start.formatted(date: .omitted, time: .shortened)
        if let e = d.end { s += " – " + e.formatted(date: .omitted, time: .shortened) }
        return s
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                Text(d.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 5).background(.black)
                Text(d.start.formatted(.dateTime.day()))
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .frame(width: 66)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(d.title).font(.title3.weight(.semibold)).foregroundStyle(.black)
                Text(timeLine).font(.subheadline).foregroundStyle(.black.opacity(0.6))
                if !d.location.isEmpty { Chip(symbol: "mappin.and.ellipse", text: d.location) }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ReminderPreview: View {
    let d: ReminderDraft
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().strokeBorder(.black, lineWidth: 2).frame(width: 28, height: 28).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(d.title).font(.title3.weight(.semibold)).foregroundStyle(.black)
                HStack(spacing: 8) {
                    if let due = d.due { Chip(symbol: "clock", text: DateText.short(due)) }
                    if !d.place.isEmpty { Chip(symbol: "mappin.and.ellipse", text: "\(d.arriving ? "Arriving" : "Leaving") \(d.place)") }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AlarmPreview: View {
    let d: AlarmDraft
    private static let order: [(Locale.Weekday, String)] = [
        (.sunday, "S"), (.monday, "M"), (.tuesday, "T"), (.wednesday, "W"),
        (.thursday, "T"), (.friday, "F"), (.saturday, "S")
    ]

    var body: some View {
        let h = d.hour % 12 == 0 ? 12 : d.hour % 12
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(h):" + String(format: "%02d", d.minute))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                Text(d.hour < 12 ? "AM" : "PM").font(.title3.weight(.medium)).foregroundStyle(.black.opacity(0.55))
            }
            .foregroundStyle(.black)
            HStack {
                Text(d.label.isEmpty ? "Alarm" : d.label).font(.subheadline).foregroundStyle(.black.opacity(0.6))
                Spacer()
                if d.repeatDays.isEmpty {
                    Text("Once").font(.caption.weight(.medium)).foregroundStyle(.black.opacity(0.5))
                } else {
                    HStack(spacing: 5) {
                        ForEach(Array(Self.order.enumerated()), id: \.offset) { _, day in
                            let on = d.repeatDays.contains(day.0)
                            Text(day.1).font(.caption2.weight(.bold))
                                .frame(width: 22, height: 22)
                                .foregroundStyle(on ? .white : .black.opacity(0.35))
                                .background(on ? Color.black : Color.black.opacity(0.06), in: Circle())
                        }
                    }
                }
            }
        }
    }
}

private struct TimerPreview: View {
    let d: TimerDraft
    @State private var drawn = false

    private var clock: String {
        let h = d.seconds / 3600, m = (d.seconds % 3600) / 60, s = d.seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(.black, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(clock).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.black)
                    .minimumScaleFactor(0.6).padding(8)
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(d.label.isEmpty ? "Timer" : d.label).font(.title3.weight(.semibold)).foregroundStyle(.black)
                Text(DateText.duration(d.seconds)).font(.subheadline).foregroundStyle(.black.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.3)) { drawn = true } }
    }
}

private struct Avatar: View {
    let name: String
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(.caption.weight(.bold)).foregroundStyle(.black)
            .frame(width: 30, height: 30).background(Color.black.opacity(0.08), in: Circle())
    }
}

private struct MessagePreview: View {
    let d: MessageDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Avatar(name: d.recipient)
                Text(d.recipient).font(.headline).foregroundStyle(.black)
            }
            HStack {
                Spacer(minLength: 40)
                Text(d.body)
                    .font(.body).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.black, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22,
                                                                   bottomTrailingRadius: 6, topTrailingRadius: 22))
            }
        }
    }
}

private struct EmailPreview: View {
    let d: EmailDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(name: d.recipient)
                VStack(alignment: .leading, spacing: 1) {
                    Text("To").font(.caption).foregroundStyle(.black.opacity(0.45))
                    Text(d.recipient).font(.subheadline.weight(.medium)).foregroundStyle(.black)
                }
            }
            Divider()
            Text(d.subject).font(.headline).foregroundStyle(.black)
            Text(d.body).font(.subheadline).foregroundStyle(.black.opacity(0.65)).lineLimit(4)
        }
    }
}

struct DirectionsPreview: View {
    let d: DirectionsDraft
    var caption = "Driving directions in Maps"
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var name: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let c = coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 1600, longitudinalMeters: 1600)),
                    interactionModes: []) {
                    Marker(name ?? d.destination, coordinate: c).tint(.black)
                }
            } else {
                Color.black.opacity(0.06)
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 90).frame(maxHeight: .infinity, alignment: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? d.destination).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(caption).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: d.destination) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = d.destination
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                coordinate = item.location.coordinate
                name = item.name
            }
        }
    }
}

// MARK: - Motion

struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 32)
            .scaleEffect(shown ? 1 : 0.95)
            .onAppear {
                withAnimation(.spring(duration: 0.55, bounce: 0.25).delay(0.1 + Double(index) * 0.1)) { shown = true }
            }
    }
}

extension View {
    func staggerIn(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}


// MARK: - Event edits (before / after)

struct EventDiffPreview: View {
    let before: EventSnapshot
    let after: EventSnapshot?
    let removing: Bool

    private func range(_ e: EventSnapshot) -> String {
        let day = e.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let sameDay = Calendar.current.isDate(e.start, inSameDayAs: e.end)
        let end = sameDay ? e.end.formatted(date: .omitted, time: .shortened)
                          : e.end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(day) · \(e.start.formatted(date: .omitted, time: .shortened)) – \(end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if removing {
                Text(before.title).font(.title3.weight(.semibold)).foregroundStyle(.black.opacity(0.45)).strikethrough()
                row("Will be removed", range(before), struck: true)
                if !before.location.isEmpty { Chip(symbol: "mappin.and.ellipse", text: before.location) }
            } else if let after {
                if after.title != before.title {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(before.title).font(.subheadline).foregroundStyle(.black.opacity(0.4)).strikethrough()
                        Text(after.title).font(.title3.weight(.semibold)).foregroundStyle(.black)
                    }
                } else {
                    Text(after.title).font(.title3.weight(.semibold)).foregroundStyle(.black)
                }
                if before.start != after.start || before.end != after.end {
                    changed("When", range(before), range(after))
                } else {
                    row("When", range(after), struck: false)
                }
                if before.location != after.location {
                    changed("Where", before.location.isEmpty ? "No location" : before.location,
                            after.location.isEmpty ? "No location" : after.location)
                } else if !after.location.isEmpty {
                    Chip(symbol: "mappin.and.ellipse", text: after.location)
                }
            }
            if before.isRecurring { Chip(symbol: "repeat", text: "Repeating event") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String, struck: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.black.opacity(0.4))
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.black.opacity(struck ? 0.45 : 0.8))
                .strikethrough(struck)
        }
    }

    private func changed(_ label: String, _ old: String, _ new: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.black.opacity(0.4))
            Text(old).font(.subheadline).foregroundStyle(.black.opacity(0.45)).strikethrough()
            HStack(spacing: 8) {
                Image(systemName: "arrow.down").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.5))
                Text(new).font(.headline).foregroundStyle(.black)
            }
        }
    }
}

/// "This event only" or "This and future events". Required before a repeating event can be changed.
struct SpanPicker: View {
    let selection: EditSpan?
    let onPick: (EditSpan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selection == nil ? "This event repeats. Apply to:" : "Applies to:")
                .font(.footnote.weight(.medium)).foregroundStyle(.black.opacity(0.6))
            HStack(spacing: 8) {
                option("This event only", .thisEvent)
                option("This and future", .futureEvents)
            }
        }
    }

    private func option(_ title: String, _ span: EditSpan) -> some View {
        let on = selection == span
        return Button { onPick(span) } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? .white : .black)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(on ? Color.black : Color.black.opacity(0.07), in: Capsule())
        }
        .buttonStyle(CardPressStyle())
    }
}
