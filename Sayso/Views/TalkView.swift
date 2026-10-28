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

    @State private var confirmClear = false
    private var showHome: Bool { model.tab == .today }

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
        .confirmationDialog("Clear the whole conversation?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear conversation", role: .destructive) { model.newChat() }
            Button("Keep it", role: .cancel) {}
        } message: { Text("Your calendar and reminders are not affected.") }
        .animation(.smooth, value: model.state)
        .task {
            model.agent.prewarm()
            NeuralVoice.shared.prepare()
            await model.refreshDay()
        }
        .onChange(of: model.tab) { _, tab in
            if tab == .today { Task { await model.refreshDay() } }
        }
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
        .confirmationDialog(model.deleting.map { "Delete “\($0.title)”?" } ?? "", isPresented: Binding(get: { model.deleting != nil }, set: { if !$0 { model.deleting = nil } }), titleVisibility: .visible, presenting: model.deleting) { item in
            if item.recurring && item.eventID != nil {
                Button("Delete this event only", role: .destructive) { Task { await model.deleteFromHome(item, span: .thisEvent) } }
                Button("Delete this and all future events", role: .destructive) { Task { await model.deleteFromHome(item, span: .futureEvents) } }
            } else {
                Button("Delete", role: .destructive) { Task { await model.deleteFromHome(item, span: .thisEvent) } }
            }
            Button("Keep", role: .cancel) {}
        }
        .alert("Couldn't do that", isPresented: Binding(get: { model.homeError != nil }, set: { if !$0 { model.homeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.homeError ?? "") }
        .overlay(alignment: .bottom) { undoToast.padding(.bottom, 84) }
        .animation(.smooth, value: model.homeUndo?.id)
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

    @ViewBuilder
    private var undoToast: some View {
        if let undo = model.homeUndo {
            HStack(spacing: 12) {
                Text("Deleted “\(undo.title)”").font(.subheadline.weight(.medium)).foregroundStyle(.black).lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { Task { await model.undoHomeDelete() } }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.black)
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            circleButton("slider.horizontal.3", label: "Settings") { showSettings = true }
            Spacer()
            tabSwitch
            Spacer()
            HStack(spacing: 8) {
                circleButton(model.speakReplies ? "speaker.wave.2.fill" : "speaker.slash", label: model.speakReplies ? "Turn off spoken replies" : "Read replies aloud", size: 40) {
                    model.speakReplies.toggle()
                }
                if model.tab == .chat, !model.messages.isEmpty {
                    Menu {
                        Button("Clear conversation", systemImage: "trash", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Color.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Chat options")
                }
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)
    }

    /// Two places, one app: your schedule, and the conversation that never goes away.
    private var tabSwitch: some View {
        HStack(spacing: 2) {
            tabButton("Today", .today)
            tabButton("Chat", .chat)
        }
        .padding(3)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    private func tabButton(_ title: String, _ tab: TalkViewModel.Tab) -> some View {
        let selected = model.tab == tab
        return Button { withAnimation(.smooth) { model.tab = tab } } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                if tab == .chat, model.hasPendingProposal, !selected {
                    Circle().frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(selected ? .black : .white.opacity(0.75))
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(selected ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
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
                    if model.messages.isEmpty && model.state == .idle { ChatEmpty(model: model) }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || !Calendar.current.isDate(message.date, inSameDayAs: model.messages[index - 1].date) {
                            DayDivider(date: message.date)
                        }
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

/// A quiet "Today" / "Yesterday" label where the conversation moves to a new day.
struct DayDivider: View {
    let date: Date
    var body: some View {
        Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(1)
            .foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity).padding(.vertical, 4)
    }
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// An empty conversation: what to say first.
struct ChatEmpty: View {
    @Bindable var model: TalkViewModel
    private let ideas = [
        "Dinner with Ankit Saturday at 8",
        "What's on tomorrow?",
        "Delete my 3pm meeting",
        "Plan my day"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask for anything.").font(.system(size: 27, weight: .medium, design: .serif).italic()).foregroundStyle(.white)
            Text("This is your one conversation. It stays here, so you can pick up where you left off.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
            ForEach(ideas, id: \.self) { idea in
                Button { Task { await model.ask(idea) } } label: {
                    Text(idea).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(.top, 30).frame(maxWidth: .infinity, alignment: .leading)
    }
}
