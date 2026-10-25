import AlarmKit
import AVFoundation
import Contacts
import EventKit
import Foundation
import FoundationModels
import Speech

/// A self-test that runs the real paths and reports exactly what failed, so an error is never just "try again".
@MainActor @Observable
final class Diagnostics {
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        var ok: Bool?          // nil = informational
        var detail: String
    }

    private(set) var rows: [Row] = []
    private(set) var isRunning = false

    var report: String {
        let device = "iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Sayso self-test (build \(build), \(device))\n" + rows.map { "\($0.ok == true ? "PASS" : $0.ok == false ? "FAIL" : "INFO") \($0.title): \($0.detail)" }.joined(separator: "\n")
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        rows = []
        defer { isRunning = false }

        let agent = AgentService()
        add("Apple Intelligence", ok: agent.isModelAvailable, agent.isModelAvailable ? "Available" : agent.unavailableReason)
        add("Tools and instructions", ok: nil, agent.sizeSummary)

        if agent.isModelAvailable {
            await step("Model reply") {
                let session = LanguageModelSession(model: .default, instructions: "Reply with one word.")
                let r = try await withTimeout(seconds: 40) { try await session.respond(to: "Say OK.").content }
                return "“\(r.prefix(20))”"
            }
            for phrase in ["Set a timer for 10 minutes",
                           "Dinner with Ankit Saturday at 8 at Nobu, and remind me to book a table",
                           "Move my dentist appointment to 5"] {
                await step("Request: \(phrase.prefix(32))…") {
                    let started = Date.now
                    let outcome = try await withTimeout(seconds: 60) { try await AgentService().respond(to: phrase) }
                    let secs = String(format: "%.1fs", Date.now.timeIntervalSince(started))
                    switch outcome {
                    case .plan(let plan): return "\(plan.actions.count) action(s) in \(secs): " + plan.actions.map(\.kindLabel).joined(separator: ", ")
                    case .question(let q): return "Asked: \(q.prefix(60)) (\(secs))"
                    case .answer(let a): return "Answered: \(a.prefix(60)) (\(secs))"
                    case .planner: return "Planner (\(secs))"
                    }
                }
            }
        }

        let plan = PlannerRouter.route("plan my day")
        let rescue = PlannerRouter.route("I'm 30 minutes behind")
        add("Plan / Rescue routing", ok: plan != nil && rescue == .rescueDay(minutesBehind: 30), "\(String(describing: plan)) / \(String(describing: rescue))")

        await step("Speech: start and stop") {
            let speech = SpeechService()
            try await withTimeout(seconds: 45) { try await speech.start() }
            await speech.cancel()
            return "Started and stopped"
        }

        add("Permissions", ok: nil, [
            "mic \(AVAudioApplication.shared.recordPermission == .granted ? "yes" : AVAudioApplication.shared.recordPermission == .denied ? "denied" : "not asked")",
            "speech \(SFSpeechRecognizer.authorizationStatus() == .authorized ? "yes" : SFSpeechRecognizer.authorizationStatus() == .notDetermined ? "not asked" : "denied")",
            "calendar \(Self.name(EKEventStore.authorizationStatus(for: .event)))",
            "reminders \(Self.name(EKEventStore.authorizationStatus(for: .reminder)))",
            "contacts \(CNContactStore.authorizationStatus(for: .contacts) == .authorized ? "yes" : "no")",
            "alarms \(AlarmManager.shared.authorizationState == .authorized ? "yes" : "no")"
        ].joined(separator: ", "))
    }

    private func step(_ title: String, _ work: () async throws -> String) async {
        do { add(title, ok: true, try await work()) } catch { add(title, ok: false, Self.describe(error)) }
    }

    private func add(_ title: String, ok: Bool?, _ detail: String) { rows.append(Row(title: title, ok: ok, detail: detail)) }

    /// The error's case name and message, which is what is needed to fix it.
    static func describe(_ error: Error) -> String {
        let raw = "\(error)"
        let text = raw == error.localizedDescription ? raw : "\(raw) | \(error.localizedDescription)"
        return String(text.prefix(220))
    }

    private static func name(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .fullAccess: "full"
        case .writeOnly: "write-only"
        case .notDetermined: "not asked"
        default: "denied"
        }
    }
}
