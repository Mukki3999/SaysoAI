import SwiftUI

/// A short animated story: the problem, then how Sayso removes it. Tap to move on, tap the left edge to go back, skip any time.
/// Nothing is asked for here. Permissions come later, the first time a feature needs one.
struct OnboardingView: View {
    var onContinue: () -> Void

    @State private var scene: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds each scene plays before moving on. The last one waits for the button.
    private static let durations: [Double] = [9, 10, 7, 8, 8, 0]
    private var last: Int { Self.durations.count - 1 }

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        var start = 0
        #if DEBUG
        start = Int(ProcessInfo.processInfo.environment["SAYSO_DEMO_ONBOARD"] ?? "") ?? 0
        #endif
        _scene = State(initialValue: start)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                content.id(scene).transition(.opacity)
                // Tap zones sit under the buttons.
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        tap.location.x < geo.size.width * 0.3 ? go(-1) : go(1)
                    })
                    .allowsHitTesting(scene < last)
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if scene == last { startButton.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: scene)
        .task(id: scene) {
            guard !reduceMotion, scene < last else { return }
            try? await Task.sleep(for: .seconds(Self.durations[scene]))
            if !Task.isCancelled { go(1) }
        }
    }

    private func go(_ step: Int) {
        let next = scene + step
        if next < 0 { return }
        if next > last { onContinue(); return }
        scene = next
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case 0: ProblemScene()
        case 1: SayItScene()
        case 2: ApproveScene()
        case 3: PlanScene()
        case 4: MenuScene()
        default: PrivacyScene()
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0...last, id: \.self) { i in
                    Segment(state: i < scene ? .done : i == scene ? .active : .todo,
                            seconds: reduceMotion || i == last ? 0 : Self.durations[i])
                        .id("\(i)-\(scene)")
                }
            }
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.caption.weight(.bold))
                    Text("Sayso").font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if scene < last {
                    Button("Skip") { onContinue() }
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                        .padding(.vertical, 6).padding(.leading, 12)
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    private var startButton: some View {
        Button(action: onContinue) {
            Text("Start talking").font(.headline).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 17).background(.white, in: Capsule())
        }
        .padding(.horizontal, 28).padding(.bottom, 20)
    }
}

/// One bar in the story progress strip.
private struct Segment: View {
    enum State { case done, active, todo }
    let state: State
    let seconds: Double
    @SwiftUI.State private var filled = false

    var body: some View {
        Capsule().fill(Color.white.opacity(0.22)).frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(.white)
                        .frame(width: state == .done || (state == .active && (filled || seconds == 0)) ? g.size.width : 0)
                }
            }
            .onAppear {
                guard state == .active, seconds > 0 else { return }
                withAnimation(.linear(duration: seconds)) { filled = true }
            }
    }
}
