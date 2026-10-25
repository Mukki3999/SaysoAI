import SwiftUI

/// Text that types itself. The full text is laid out invisibly first so nothing jumps as it grows.
struct Typewriter: View {
    let text: String
    var perChar: Double = 0.03
    var delay: Double = 0
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text).opacity(0)
            Text(String(text.prefix(shown)))
        }
        .task(id: text) {
            if reduceMotion { shown = text.count; return }
            shown = 0
            try? await Task.sleep(for: .seconds(delay))
            for i in 1...max(text.count, 1) {
                if Task.isCancelled { return }
                shown = i
                try? await Task.sleep(for: .seconds(perChar))
            }
        }
    }
}

/// Runs timed steps once when a scene appears. With Reduce Motion on, every step happens at once.
extension View {
    func script(_ steps: [(after: Double, run: () -> Void)]) -> some View {
        modifier(ScriptModifier(steps: steps))
    }
}

private struct ScriptModifier: ViewModifier {
    let steps: [(after: Double, run: () -> Void)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task {
            var elapsed = 0.0
            for step in steps {
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(max(step.after - elapsed, 0)))
                    if Task.isCancelled { return }
                }
                elapsed = max(elapsed, step.after)
                step.run()
            }
        }
    }
}

/// Serif headline used across scenes.
struct SceneHeadline: View {
    let text: String
    var delay: Double = 0.2
    var body: some View {
        Typewriter(text: text, perChar: 0.028, delay: delay)
            .font(.system(size: 36, weight: .medium, design: .serif).italic())
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SceneCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 17)).foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// A compact white row that matches the real approval cards.
struct MiniRow: View {
    let symbol: String
    let kind: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(.black, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.black.opacity(0.4))
                Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
