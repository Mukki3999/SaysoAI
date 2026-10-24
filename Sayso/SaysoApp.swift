import SwiftUI

@main
struct SaysoApp: App {
    @State private var model = TalkViewModel()
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    /// Debug-only: lets the simulator, which has no Apple Intelligence, show the main UI.
    private static var skipAvailabilityCheck: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SAYSO_SKIP_AVAILABILITY"] == "1"
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !model.agent.isModelAvailable && !Self.skipAvailabilityCheck {
                    UnsupportedDeviceView(reason: model.agent.unavailableReason)
                } else if !hasOnboarded {
                    OnboardingView { hasOnboarded = true }
                } else {
                    TalkView(model: model)
                }
            }
        }
    }
}
