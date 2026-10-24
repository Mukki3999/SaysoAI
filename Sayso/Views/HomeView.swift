import SwiftUI

/// The idle screen: your day in one place, with the AI up front.
struct HomeView: View {
    @Bindable var model: TalkViewModel
    @Environment(\.openURL) private var openURL

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    private let suggestions = ["What's my day look like?", "What's on tomorrow?", "Am I free Saturday?"]
    private let examples = [
        "Dinner with Ankit Saturday at 8, then remind me to book a table",
        "Text Sam I'm late and take me to Blue Bottle",
        "Wake me at 6:30 on weekdays"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting).font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                switch model.day.access {
                case .granted: granted
                case .notAsked: connectCard
                case .denied: deniedCard
                }
                if model.day.access != .granted || model.day.items.isEmpty { tryRow }
            }
            .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Granted

    @ViewBuilder
    private var granted: some View {
        if let briefing = model.day.briefing {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").font(.body.weight(.semibold)).padding(.top, 3)
                Text(briefing).font(.title3).fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity)
        }
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { text in
                    Button { Task { await model.ask(text) } } label: {
                        Text(text).font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -24)

        ForEach(model.day.sections) { section in
            VStack(alignment: .leading, spacing: 10) {
                Text(section.title.uppercased()).font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                if section.items.isEmpty {
                    Text("Nothing planned").font(.subheadline).foregroundStyle(.tertiary)
                }
                ForEach(section.items) { item in row(item) }
            }
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        let past = item.kind == .event && (item.end ?? .distantFuture) < .now
        return HStack(alignment: .top, spacing: 14) {
            Text(timeLabel(item)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing).padding(.top, 14)
            HStack(spacing: 12) {
                icon(item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body.weight(.medium)).lineLimit(2)
                    if !item.detail.isEmpty { Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .opacity(past ? 0.4 : 1)
    }

    @ViewBuilder
    private func icon(_ item: AgendaItem) -> some View {
        switch item.kind {
        case .event: Image(systemName: "calendar").foregroundStyle(.secondary)
        case .reminder: Image(systemName: "circle").foregroundStyle(.secondary)
        case .alarm: Image(systemName: item.start == nil ? "timer" : "alarm").foregroundStyle(.secondary)
        }
    }

    private func timeLabel(_ item: AgendaItem) -> String {
        guard let start = item.start else { return "Now" }
        if item.kind == .reminder, start < Calendar.current.startOfDay(for: .now) { return "Overdue" }
        if item.allDay { return item.kind == .reminder ? "Due" : "All day" }
        return start.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Not connected

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your day, in one place", systemImage: "sparkles").font(.headline)
            Text("Sayso can show your calendar, reminders and alarms here, and answer questions like “what's on tomorrow?”. It all stays on your iPhone.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await model.connectDay() } } label: {
                Text("Show my day").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.primary, in: Capsule())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar access is off").font(.headline)
            Text("Turn it on in Settings to see your day here.").font(.subheadline).foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.bordered).tint(.primary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var tryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try saying").font(.footnote).foregroundStyle(.tertiary)
            ForEach(examples, id: \.self) { Text("“\($0)”").font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
