import SwiftUI

/// Type a request instead of saying it. Goes through the same path as speech.
struct TypeSheet: View {
    var onSend: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            TextField("Ask Sayso or tell it what to do", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.title3)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
            HStack {
                Spacer()
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.headline).foregroundStyle(.black)
                        .frame(width: 44, height: 44).background(Color.white, in: Circle())
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            }
        }
        .padding(24)
        .presentationDetents([.height(190)])
        .presentationBackground(Color(white: 0.09))
        .presentationCornerRadius(28)
        .onAppear { focused = true }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        dismiss()
        onSend(t)
    }
}
