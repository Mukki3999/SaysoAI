import SwiftUI

struct UnsupportedDeviceView: View {
    var reason: String
    var model: TalkViewModel

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
            // Planning never depends on the language model, so it still works here.
            Button("Plan my day manually") { model.showManualPlan = true }
                .buttonStyle(.borderedProminent).padding(.top, 8)
            Button("Browse a menu photo") { model.showMenu = true }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .plannerSheets(model)
    }
}
