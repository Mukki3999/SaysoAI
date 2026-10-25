import PhotosUI
import SwiftUI

struct TalkView: View {
    @Bindable var model: TalkViewModel
    @State private var showSettings = false
    @State private var showType = false
    @State private var pickedPhoto: PhotosPickerItem?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var idle: Bool { model.state == .idle }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if idle {
                    HomeView(model: model).transition(.opacity)
                } else {
                    Spacer(minLength: 0)
                    centerContent.transition(.opacity)
                    Spacer(minLength: 0)
                }
                WaveView(mode: model.waveMode, level: model.speech.level)
                    .frame(height: idle ? 48 : 150)
                Text(model.caption)
                    .font(.footnote).foregroundStyle(.white.opacity(0.5))
                    .frame(height: 20).padding(.top, 4)
                controls.padding(.top, 10).padding(.bottom, 12)
            }
        }
        .animation(.smooth, value: idle)
        .task { await model.refreshDay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshDay() } }
        }
        .onChange(of: model.plan == nil) { _, closed in
            if closed { Task { await model.refreshDay() } }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await model.handlePhoto(item) }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showType) { TypeSheet { text in Task { await model.ask(text) } } }
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

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            circleButton("slider.horizontal.3", label: "Settings") { showSettings = true }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.caption.weight(.bold))
                Text("Sayso").font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private func circleButton(_ symbol: String, label: String, size: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.white)
                .frame(width: size, height: size).background(Color.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Center content (everything except idle)

    @ViewBuilder
    private var centerContent: some View {
        VStack(spacing: 18) {
            switch model.state {
            case .idle:
                EmptyView()
            case .listening:
                Text(model.speech.transcript.isEmpty ? "Listening…" : model.speech.transcript)
                    .font(.system(size: 34, weight: .medium, design: .serif).italic())
                    .foregroundStyle(model.speech.transcript.isEmpty ? .white.opacity(0.4) : .white)
                    .multilineTextAlignment(.center)
            case .thinking:
                Text(model.spoken)
                    .font(.system(size: 28, weight: .medium, design: .serif).italic())
                    .foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                Label("Thinking", systemImage: "sparkles").font(.footnote).foregroundStyle(.white.opacity(0.5))
                    .symbolEffect(.pulse)
            case .answer(let a):
                replyCard(title: model.spoken, body: a)
                pillButton("Done") { model.dismissError() }
            case .question(let q):
                replyCard(title: model.spoken, body: q)
                Text("Hold or tap the mic to answer").font(.footnote).foregroundStyle(.white.opacity(0.5))
            case .done(let summary):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44, weight: .light)).foregroundStyle(.white)
                Text(summary).font(.system(size: 28, weight: .medium, design: .serif).italic()).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            case .error(let message):
                Text(message).font(.title3).foregroundStyle(.white).multilineTextAlignment(.center)
                if model.speech.permissionDenied || model.errorNeedsSettings {
                    pillButton("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else {
                    pillButton("Try again") { model.dismissError() }
                }
            }
        }
        .padding(.horizontal, 28)
        .animation(.smooth, value: model.state)
    }

    private func replyCard(title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(.black)
                .frame(width: 44, height: 44).background(Color.black.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.black).lineLimit(2)
                Text(body).font(.body).foregroundStyle(.black.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 11).background(.white, in: Capsule())
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            circleButton("keyboard", label: "Type a request", size: 56) { showType = true }
                .opacity(idle ? 1 : 0.3).disabled(!idle)
            Spacer()
            micButton
            Spacer()
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 21, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Plan from a photo")
            .opacity(idle ? 1 : 0.3).disabled(!idle)
        }
        .padding(.horizontal, 28)
    }

    private var micButton: some View {
        let listening = model.state == .listening
        return ZStack {
            Circle().fill(Color.white.opacity(0.12)).frame(width: 112, height: 112)
                .scaleEffect(listening ? 1.08 + model.speech.level * 0.3 : 1)
                .animation(.easeOut(duration: 0.12), value: model.speech.level)
            Circle().fill(.white).frame(width: 84, height: 84)
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: 30)).foregroundStyle(.black)
                .symbolEffect(.variableColor.iterative, isActive: listening)
        }
        .frame(width: 112, height: 112)
        .contentShape(Circle())
        .animation(.spring(duration: 0.3), value: listening)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.pressBegan() }
                .onEnded { _ in model.pressEnded() }
        )
        .accessibilityLabel("Hold to talk")
        .accessibilityAddTraits(.isButton)
    }
}
