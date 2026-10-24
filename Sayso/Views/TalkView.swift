import SwiftUI

struct TalkView: View {
    @Bindable var model: TalkViewModel
    @State private var showSettings = false
    @Environment(\.openURL) private var openURL

    private let examples = [
        "Remind me to call mom tomorrow at 6",
        "Set an alarm for 7 am on weekdays",
        "Lunch with Sam Friday at noon",
        "Start a 10 minute timer"
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                centerText
                Spacer(minLength: 0)
                WaveView(mode: model.waveMode, level: model.speech.level)
                    .frame(height: 170)
                micButton
                    .padding(.top, 8)
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(item: $model.plan) { plan in ConfirmationSheet(model: model, plan: plan) }
        .sheet(item: $model.messageRequest) { request in
            MessageComposer(request: request) { model.messageRequest = nil }.ignoresSafeArea()
        }
        .sheet(item: $model.emailRequest) { request in
            MailComposer(request: request) { model.emailRequest = nil }.ignoresSafeArea()
        }
        .onChange(of: model.mailtoURL) { _, url in
            if let url { openURL(url); model.mailtoURL = nil }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var centerText: some View {
        VStack(spacing: 14) {
            switch model.state {
            case .idle:
                if model.recent.isEmpty {
                    Text("Try saying…").font(.footnote).foregroundStyle(.tertiary)
                    ForEach(examples, id: \.self) { phrase in
                        Text("“\(phrase)”").font(.body).foregroundStyle(.secondary)
                    }
                } else {
                    recentList
                }
            case .listening:
                Text(model.speech.transcript.isEmpty ? "Listening…" : model.speech.transcript)
                    .font(.system(size: 28, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(model.speech.transcript.isEmpty ? .tertiary : .primary)
            case .thinking:
                Text(model.speech.transcript).font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Thinking…").font(.footnote).foregroundStyle(.tertiary)
            case .question(let q):
                Text(q).font(.title3).multilineTextAlignment(.center)
                Text("Hold to answer").font(.footnote).foregroundStyle(.tertiary)
            case .done(let summary):
                Image(systemName: "checkmark").font(.title.weight(.light))
                Text(summary).font(.title3).multilineTextAlignment(.center)
            case .error(let message):
                Text(message).font(.title3).multilineTextAlignment(.center)
                if model.speech.permissionDenied {
                    Button("Open Settings") { openSettings() }.buttonStyle(.bordered).tint(.primary)
                } else {
                    Button("Try again") { model.dismissError() }.buttonStyle(.bordered).tint(.primary)
                }
            }
        }
        .padding(.horizontal, 32)
        .animation(.smooth, value: model.state)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.footnote).foregroundStyle(.tertiary)
            ForEach(model.recent.prefix(4)) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.symbol).frame(width: 22).foregroundStyle(.secondary)
                    Text(item.title).lineLimit(1)
                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: 340)
    }

    private var micButton: some View {
        let listening = model.state == .listening
        return Circle()
            .fill(Color.primary)
            .frame(width: listening ? 88 : 76, height: listening ? 88 : 76)
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(.systemBackground))
            }
            .shadow(color: .primary.opacity(0.15), radius: listening ? 24 : 10, y: 4)
            .animation(.spring(duration: 0.3), value: listening)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.pressBegan() }
                    .onEnded { _ in model.pressEnded() }
            )
            .accessibilityLabel("Hold to talk")
            .accessibilityAddTraits(.isButton)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
