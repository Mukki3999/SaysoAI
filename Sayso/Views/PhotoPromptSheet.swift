import SwiftUI

/// After choosing a photo: say what you want done with it. Optional, so a bare "Send" still works.
struct PhotoPromptSheet: View {
    let photo: PendingPhoto
    let onSend: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private let suggestions = ["Add this to my calendar", "Remind me about this", "What should I eat?"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("What should Sayso do with this?")
                    .font(.system(size: 24, weight: .medium, design: .serif).italic()).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.top, 28)
                if let image = photo.image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { onSend(s) } label: {
                                Text(s).font(.footnote.weight(.medium)).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    TextField("Or tell me what you want…", text: $text, axis: .vertical)
                        .focused($focused).lineLimit(1...4)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Button { onSend(text) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.black)
                            .frame(width: 46, height: 46).background(.white, in: Circle())
                    }
                    .accessibilityLabel("Send")
                }
                Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationBackground(.black)
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
    }
}
