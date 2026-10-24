import PhotosUI
import SwiftUI

struct TalkView: View {
    @Bindable var model: TalkViewModel
    @State private var showSettings = false
    @State private var pickedPhoto: PhotosPickerItem?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if model.state == .idle {
                    HomeView(model: model).transition(.opacity)
                } else {
                    Spacer(minLength: 0)
                    centerText
                    Spacer(minLength: 0)
                }
                WaveView(mode: model.waveMode, level: model.speech.level)
                    .frame(height: 120)
                HStack {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3).foregroundStyle(.primary)
                            .frame(width: 52, height: 52)
                            .background(Color.primary.opacity(0.07), in: Circle())
                    }
                    .accessibilityLabel("Plan from a photo")
                    .opacity(model.state == .idle ? 1 : 0.3)
                    .disabled(model.state != .idle)
                    Spacer()
                    micButton
                    Spacer()
                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                Text(model.caption)
                    .font(.footnote).foregroundStyle(.tertiary)
                    .frame(height: 20).padding(.top, 10).padding(.bottom, 18)
            }
        }
        .animation(.smooth, value: model.state == .idle)
        .task { await model.refreshDay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshDay() } }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await model.handlePhoto(item) }
        }
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
                EmptyView()
            case .listening:
                Text(model.speech.transcript.isEmpty ? "Listening…" : model.speech.transcript)
                    .font(.system(size: 28, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(model.speech.transcript.isEmpty ? .tertiary : .primary)
            case .thinking:
                Text(model.spoken).font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Thinking…").font(.footnote).foregroundStyle(.tertiary)
            case .answer(let a):
                Image(systemName: "sparkles").font(.title2)
                Text(a).font(.title3).multilineTextAlignment(.center)
                Button("Done") { model.dismissError() }.buttonStyle(.bordered).tint(.primary).padding(.top, 4)
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
