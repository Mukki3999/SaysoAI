import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    // TODO before submission: replace with your real URLs.
    private let privacyURL = URL(string: "https://example.com/sayso/privacy")!
    private let supportURL = URL(string: "https://example.com/sayso/support")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link("Privacy policy", destination: privacyURL)
                    Link("Support", destination: supportURL)
                }
                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Sayso runs on your iPhone. Your voice and requests never leave it.")
                }
            }
            .navigationTitle("Sayso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
