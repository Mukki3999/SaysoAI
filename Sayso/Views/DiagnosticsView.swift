import SwiftUI

struct DiagnosticsView: View {
    @State private var diagnostics = Diagnostics()

    var body: some View {
        List {
            Section {
                Button(diagnostics.isRunning ? "Running…" : "Run self-test") { Task { await diagnostics.run() } }
                    .disabled(diagnostics.isRunning)
            } footer: {
                Text("Runs the model, a few sample requests and the microphone. It can take a minute the first time. Nothing is saved or sent anywhere.")
            }
            if !diagnostics.rows.isEmpty {
                Section("Results") {
                    ForEach(diagnostics.rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(row.title, systemImage: row.ok == true ? "checkmark.circle.fill" : row.ok == false ? "xmark.octagon.fill" : "info.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.ok == false ? Color.red : Color.primary)
                            Text(row.detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                if !diagnostics.isRunning {
                    Section { ShareLink("Share results", item: diagnostics.report) }
                }
            }
        }
        .navigationTitle("Self-test")
        .navigationBarTitleDisplayMode(.inline)
    }
}
