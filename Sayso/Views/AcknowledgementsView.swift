import SwiftUI

/// Credits for the open-source pieces Sayso uses. Their licenses ask for this notice.
struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                credit("Kokoro-82M", "Text-to-speech model by hexgrad, licensed under Apache License 2.0. Converted to Core ML by aufklarer.")
                credit("speech-swift", "Swift library for on-device speech models by soniqo, licensed under Apache License 2.0.")
            } footer: {
                Text("Licensed under the Apache License, Version 2.0. You may obtain a copy at apache.org/licenses/LICENSE-2.0. The software is provided “as is”, without warranties or conditions of any kind.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.body.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Public pages for the App Store listing and Settings.
enum SaysoLinks {
    static let privacy = URL(string: "https://sparkly-flat-825.notion.site/Sayso-Privacy-Policy-411c24ebe50e80a797a5cb2f7d385c86")!
    static let terms = URL(string: "https://sparkly-flat-825.notion.site/Sayso-Terms-of-Service-411c24ebe50e803f9d54e93346e9e007")!
    static let support = URL(string: "https://sparkly-flat-825.notion.site/Sayso-Support-411c24ebe50e80d3bda8c78e6320058a")!
}
