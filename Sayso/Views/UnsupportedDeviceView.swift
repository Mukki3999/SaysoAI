import SwiftUI

struct UnsupportedDeviceView: View {
    var reason: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Sayso can't run here")
                .font(.title2.weight(.semibold))
            Text(reason)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
