import SwiftUI

struct OnboardingView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "sparkle").font(.title3.weight(.bold))
                Text("Sayso").font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            Text("Your life,\nin one place.")
                .font(.system(size: 50, weight: .medium, design: .serif).italic())
                .multilineTextAlignment(.center).foregroundStyle(.white)
                .padding(.top, 18)
            Text("Speak it. Your phone does it.")
                .font(.title3).foregroundStyle(.white.opacity(0.55)).padding(.top, 14)
            Text("Say what you need, approve what Sayso sets up, and see your whole day here. Your voice is processed on your iPhone.")
                .font(.body).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 40).padding(.top, 22)
            Spacer()
            WaveView(mode: .idle, level: 0).frame(height: 110)
            Button(action: onContinue) {
                Text("Get started").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(.white, in: Capsule())
            }
            .padding(.horizontal, 32).padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
