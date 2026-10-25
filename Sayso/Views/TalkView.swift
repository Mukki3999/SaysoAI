import PhotosUI
import SwiftUI

/// The main screen: your day when the thread is empty, a conversation once you start talking.
struct TalkView: View {
    @Bindable var model: TalkViewModel
    @State private var showSettings = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var showHome: Bool { model.messages.isEmpty && model.state != .listening && model.state != .thinking }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if showHome {
                    HomeView(model: model).transition(.opacity)
                } else {
                    thread.transition(.opacity)
                }
                if model.state == .listening {
                    WaveView(mode: model.waveMode, level: model.speech.level).frame(height: 56).transition(.opacity)
                }
                Composer(model: model, onLibrary: { showPhotoPicker = true }, onCamera: { showCamera = true })
            }
        }
        .animation(.smooth, value: showHome)
        .animation(.smooth, value: model.state)
        .task { await model.refreshDay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshDay() } }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await model.loadPhoto(item) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in Task { model.receivePhoto(data) } }.ignoresSafeArea()
        }
        .plannerSheets(model)
        .sheet(isPresented: $showSettings) { SettingsSheet(planner: model.planner) }
        .sheet(item: $model.reviewing) { plan in ConfirmationSheet(model: model, plan: plan) }
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
            HStack(spacing: 8) {
                circleButton(model.speakReplies ? "speaker.wave.2.fill" : "speaker.slash", label: model.speakReplies ? "Turn off spoken replies" : "Read replies aloud", size: 40) {
                    model.speakReplies.toggle()
                }
                if !model.messages.isEmpty {
                    circleButton("square.and.pencil", label: "New chat", size: 40) { model.newChat() }
                }
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)
    }

    private func circleButton(_ symbol: String, label: String, size: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.white)
                .frame(width: size, height: size).background(Color.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.messages) { message in
                        MessageRow(model: model, message: message).id(message.id)
                    }
                    if model.state == .listening {
                        ListeningRow(transcript: model.speech.transcript).id("live")
                    }
                    if model.state == .thinking {
                        ThinkingRow(status: model.thinkingStatus) { model.cancelThinking() }.id("live")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { scroll(proxy) }
            .onChange(of: model.state) { scroll(proxy) }
            .onChange(of: model.speech.transcript) { scroll(proxy, animated: false) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated { withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
