import SwiftUI

/// The idle screen: your life in one place, with the AI up front.
struct HomeView: View {
    @Bindable var model: TalkViewModel
    @State private var filter: DayFilter = .today
    @Environment(\.openURL) private var openURL

    private var greeting: String {
        let part: String
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Good night"
        }
        return "\(part) · \(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }

    private var headline: String {
        model.day.briefing ?? (model.day.items.isEmpty ? "Your AI is ready for your day." : "Here's your day.")
    }

    private var shown: [AgendaItem] { model.day.items(for: filter) }

    private let examples = [
        "Dinner with Ankit Saturday at 8, then remind me to book a table",
        "Wake me at 6:30 on weekdays",
        "Text Sam I'm late and take me to Blue Bottle"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting.uppercased()).font(.caption.weight(.semibold)).tracking(1.1)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(headline)
                        .font(.system(size: 29, weight: .medium, design: .serif).italic())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                .padding(.top, 6)

                pills

                VStack(alignment: .leading, spacing: 14) {
                    Text(sectionTitle).font(.title3).foregroundStyle(.white)
                    if shown.isEmpty {
                        emptyCard
                    } else {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            AgendaCard(item: item, featured: index == 0, stacked: index == 0 && shown.count > 1)
                                .padding(.top, index == 0 && shown.count > 1 ? 20 : 0)
                                .staggerIn(index)
                        }
                    }
                }
                .id(filter)

                switch model.day.access {
                case .granted: EmptyView()
                case .notAsked: connectCard
                case .denied: deniedCard
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.93),
                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private var sectionTitle: String {
        switch filter {
        case .today: shown.contains { $0.start == nil || $0.start! >= .now } ? "Up next" : "Today"
        case .tomorrow: "Tomorrow"
        case .upcoming: "Coming up"
        }
    }

    private var pills: some View {
        HStack(spacing: 8) {
            ForEach(DayFilter.allCases) { f in
                Button { withAnimation(.smooth) { filter = f } } label: {
                    Text(f.rawValue).font(.subheadline.weight(.medium))
                        .foregroundStyle(filter == f ? .black : .white)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(filter == f ? Color.white : Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing here yet").font(.headline).foregroundStyle(.white)
            Text("Tap the mic and try").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            Text("“\(examples[Calendar.current.component(.minute, from: .now) % examples.count])”")
                .font(.system(size: 20, design: .serif).italic()).foregroundStyle(.white.opacity(0.85))
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("See your whole calendar here", systemImage: "sparkles").font(.headline)
            Text("Connect Calendar and Reminders to see everything in one place, and ask “what's on tomorrow?”. It all stays on your iPhone.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            Button { Task { await model.connectDay() } } label: {
                Text("Connect").font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 20).padding(.vertical, 10).background(.white, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar access is off").font(.headline)
            Text("Turn it on in Settings to see your whole day here.").font(.subheadline).foregroundStyle(.white.opacity(0.6))
            Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                Text("Open Settings").font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 20).padding(.vertical, 10).background(.white, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
