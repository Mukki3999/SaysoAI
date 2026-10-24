import SwiftUI

struct OnboardingView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Sayso")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text("Speak it. Your phone does it.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text("Tap or hold the button, say what you need, and approve what Sayso sets up. Your voice is processed on your iPhone.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 28)
            Spacer()
            WaveView(mode: .idle, level: 0).frame(height: 120)
            Button(action: onContinue) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
            .clipShape(Capsule())
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
}
