import Foundation
import Observation

/// The user's planning preferences, saved on the device.
@MainActor @Observable
final class PlannerSettings {
    var plan: PlanSettings { didSet { save() } }
    var focus: FocusPreference { didSet { save() } }

    private let key = "sayso.planner.settings"

    private struct Stored: Codable {
        var plan: PlanSettings
        var focus: FocusPreference
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            plan = s.plan
            focus = s.focus
        } else {
            plan = PlanSettings()
            focus = .morning
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(plan: plan, focus: focus)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension FocusPreference {
    /// Understands "mornings", "after lunch", "doesn't matter" and so on. Anything else means no preference.
    static func parse(_ text: String) -> FocusPreference {
        let t = text.lowercased()
        if t.contains("morning") || t.contains("early") { return .morning }
        if t.contains("afternoon") || t.contains("after lunch") { return .afternoon }
        if t.contains("evening") || t.contains("night") || t.contains("late") { return .evening }
        return .none
    }
}

enum SpokenMinutes {
    /// "30", "45 minutes", "an hour", "half an hour", "an hour and a half", "two hours".
    static func parse(_ text: String) -> Int? {
        let t = text.lowercased()
        if t.contains("hour and a half") || t.contains("hour and half") { return 90 }
        if t.contains("half an hour") || t.contains("half hour") { return 30 }
        let words = ["fifteen": 15, "twenty": 20, "thirty": 30, "forty five": 45, "forty-five": 45, "sixty": 60, "ninety": 90,
                     "one": 1, "two": 2, "three": 3, "four": 4]
        var number: Double?
        if let m = t.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) { number = Double(t[m]) }
        else if let w = words.first(where: { t.contains($0.key) }) { number = Double(w.value) }
        else if t.contains("an hour") || t.contains("a hour") { number = 1 }
        guard let n = number else { return nil }
        let isHours = t.range(of: #"\b(hours?|hrs?|h)\b"#, options: .regularExpression) != nil
        let value = isHours ? n * 60 : n
        return Int(value)
    }
}
