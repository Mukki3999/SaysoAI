import Foundation

/// Spots "plan my day" and "I'm behind" before the language model sees the request. Those two start their own flows,
/// so keeping them out of the model's tool list leaves its small context window for everything else.
enum PlannerRouter {
    static func route(_ text: String) -> PlannerIntent? {
        let t = text.lowercased().replacingOccurrences(of: "’", with: "'")

        // A message to someone ("tell Sam I'm running behind") is not a request to re-plan.
        let messaging = t.range(of: #"\b(text|tell|message|email|call|dm|whatsapp)\b"#, options: .regularExpression) != nil

        let rescue = #"\b(behind|re-?plan (the )?rest|rest of my day|rescue my day|catch up on my day)\b"#
        if !messaging, t.range(of: rescue, options: .regularExpression) != nil {
            let hasNumber = t.range(of: #"\d|\b(hour|half|fifteen|twenty|thirty|forty|sixty|ninety)\b"#, options: .regularExpression) != nil
            if hasNumber, let minutes = SpokenMinutes.parse(t) { return .rescueDay(minutesBehind: minutes) }
            // "Re-plan the rest of my day" with no number means nothing is lost yet.
            if t.contains("re-plan") || t.contains("replan") || t.contains("rest of my day") { return .rescueDay(minutesBehind: 0) }
            return .rescueDay(minutesBehind: nil)
        }

        let plan = #"\b(plan|organi[sz]e|schedule|map out|lay out)\s+(out\s+)?(my|the|our)?\s*(whole\s+|entire\s+)?(day|today)\b|\bplan today\b"#
        if let m = t.range(of: plan, options: .regularExpression) {
            // "Plan my day: finish the deck, gym" carries the to-do list with it.
            var rest = String(t[m.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " :,.-–"))
            for lead in ["i need to ", "i have to ", "i want to ", "i've got to ", "so i can ", "for me "] where rest.hasPrefix(lead) { rest = String(rest.dropFirst(lead.count)) }
            return .planDay(mustDos: rest.count >= 6 ? rest : nil)
        }
        // "Help me plan my calendar", "I have a busy day tomorrow, can you help me plan it": same planner.
        let loose = #"\b(plan|organi[sz]e|map out|lay out|sort out|structure|manage)\s+(out\s+)?(my|the|our)?\s*(whole\s+|entire\s+)?(tomorrow|calendar|schedule|week)\b|\bplan (today|tomorrow)\b|\b(busy|packed|hectic|crazy|full) (day|tomorrow)\b"#
        if !messaging, t.range(of: loose, options: .regularExpression) != nil { return .planDay(mustDos: nil) }
        return nil
    }
}
