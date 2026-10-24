import SwiftUI

/// Flowing ribbon lines, white and black. Calm when idle, swells with the voice while listening.
struct WaveView: View {
    enum Mode { case idle, listening, thinking }
    var mode: Mode
    var level: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let mid = size.height / 2
                let amp = amplitude(t: t, height: size.height)
                // hairline horizon
                var base = Path()
                base.move(to: CGPoint(x: 0, y: mid))
                base.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(base, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)

                for i in 0..<7 {
                    let f = Double(i)
                    var path = Path()
                    let speed = (mode == .thinking ? 1.6 : 0.8) + f * 0.12
                    let freq = 1.2 + f * 0.35
                    let phase = t * speed + f * 0.9
                    let weight = 1.0 - f / 9
                    var x: CGFloat = 0
                    while x <= size.width {
                        let u = Double(x / size.width)
                        let envelope = pow(sin(.pi * u), 2.2)
                        let y = mid + CGFloat(sin(u * .pi * 2 * freq + phase) * envelope * amp * weight)
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += 3
                    }
                    let opacity = 0.14 + 0.5 * weight
                    ctx.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: i == 0 ? 1.6 : 0.8)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func amplitude(t: TimeInterval, height: CGFloat) -> Double {
        let h = Double(height)
        switch mode {
        case .idle: return h * (0.05 + 0.02 * sin(t * 0.8))
        case .listening: return h * (0.06 + 0.42 * level)
        case .thinking: return h * (0.14 + 0.08 * sin(t * 2.2))
        }
    }
}
