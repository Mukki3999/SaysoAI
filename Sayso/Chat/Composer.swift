import PhotosUI
import SwiftUI

/// The bar at the bottom: add things, type, talk.
struct Composer: View {
    @Bindable var model: TalkViewModel
    let onLibrary: () -> Void
    let onCamera: () -> Void
    @FocusState private var focused: Bool
    @State private var askBehind = false

    private var hasContent: Bool { !model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.attachment != nil }
    private var listening: Bool { model.state == .listening }

    var body: some View {
        VStack(spacing: 8) {
            if let photo = model.attachment { attachmentRow(photo) }
            HStack(alignment: .bottom, spacing: 10) {
                plusMenu
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(model.attachment == nil ? "Message Sayso" : "What should I do with this?", text: $model.input, axis: .vertical)
                        .focused($focused).lineLimit(1...5).submitLabel(.send)
                        .onSubmit { model.submitComposer() }
                        .padding(.leading, 16).padding(.vertical, 12)
                        .disabled(listening)
                    trailing
                }
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        .confirmationDialog("How far behind are you?", isPresented: $askBehind) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { m in Button("\(m) minutes") { model.startRescue(minutes: m) } }
        }
    }

    // MARK: Pieces

    private var plusMenu: some View {
        Menu {
            Button { onLibrary() } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
            if CameraPicker.isAvailable { Button { onCamera() } label: { Label("Take a photo", systemImage: "camera") } }
            Divider()
            Button { model.startPlanning() } label: { Label("Plan my day", systemImage: "sparkles") }
            Button { askBehind = true } label: { Label("Running behind?", systemImage: "gauge.with.dots.needle.67percent") }
            Button { model.showMenu = true } label: { Label("Menu helper", systemImage: "fork.knife") }
        } label: {
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(Color.white.opacity(0.12), in: Circle())
        }
        .disabled(!model.canSend)
        .accessibilityLabel("Add")
    }

    @ViewBuilder
    private var trailing: some View {
        if hasContent && !listening {
            Button { focused = false; model.submitComposer() } label: {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34).background(.white, in: Circle())
            }
            .padding(6)
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
        } else {
            mic.padding(6)
        }
    }

    private var mic: some View {
        ZStack {
            Circle().fill(listening ? Color.white : Color.white.opacity(0.9)).frame(width: 34, height: 34)
                .scaleEffect(listening ? 1.15 + model.speech.level * 0.5 : 1)
                .animation(.easeOut(duration: 0.12), value: model.speech.level)
            Image(systemName: listening ? "waveform" : "mic.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                .symbolEffect(.variableColor.iterative, isActive: listening)
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in focused = false; model.pressBegan() }
                .onEnded { _ in model.pressEnded() }
        )
        .accessibilityLabel("Hold to talk, or tap once")
        .accessibilityAddTraits(.isButton)
    }

    private func attachmentRow(_ photo: PendingPhoto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack(alignment: .topTrailing) {
                    if let image = photo.image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Button { model.attachment = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("Remove photo")
                }
                Spacer()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(["Add this to my calendar", "Remind me about this", "What should I eat?"], id: \.self) { s in
                        Button { model.input = ""; let p = model.attachment; model.attachment = nil; if let p { Task { await model.sendPhoto(p, text: s) } } } label: {
                            Text(s).font(.footnote.weight(.medium)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 4)
    }
}
