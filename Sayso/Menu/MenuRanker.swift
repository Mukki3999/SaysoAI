import Foundation
import FoundationModels

/// The model's raw answer for one pick, before it is checked.
struct RawPick: Equatable, Sendable {
    var number: Int
    var name: String
    var reason: String
}

/// Every pick has to be a dish in the candidate list. Anything else is dropped.
enum PickValidator {
    static func validate(_ raw: [RawPick], candidates: [MenuItem], limit: Int = 3) -> [MenuPick] {
        var out: [MenuPick] = []
        var used: Set<UUID> = []
        for pick in raw {
            let reason = pick.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty, let item = match(pick, in: candidates), used.insert(item.id).inserted else { continue }
            out.append(MenuPick(item: item, reason: String(reason.prefix(140))))
            if out.count == limit { break }
        }
        return out
    }

    /// By number if the name agrees with that dish, otherwise by exact name. Never by guesswork.
    private static func match(_ pick: RawPick, in candidates: [MenuItem]) -> MenuItem? {
        let name = MenuParser.normalize(pick.name)
        guard !name.isEmpty else { return nil }
        if (1...max(candidates.count, 1)).contains(pick.number), candidates.indices.contains(pick.number - 1) {
            let item = candidates[pick.number - 1]
            let other = MenuParser.normalize(item.name)
            if other == name || other.contains(name) || name.contains(other) { return item }
        }
        return candidates.first { MenuParser.normalize($0.name) == name }
    }
}

enum MenuRanker {
    @Generable
    struct RankedPick {
        @Guide(description: "The number of the dish in the list")
        var number: Int
        @Guide(description: "The dish name exactly as listed")
        var name: String
        @Guide(description: "One short sentence, at most 14 words, on why it fits. Use only the listed text")
        var reason: String
    }

    @Generable
    struct RankedPicks {
        var picks: [RankedPick]
    }

    /// Top 3 from `candidates` (already filtered and capped at about 25). Asks again once if picks fail validation,
    /// then fills from the best-scored candidates with a reason built from facts.
    static func rank(_ candidates: [MenuItem], _ prefs: MenuPreferences) async throws -> [MenuPick] {
        let wanted = min(3, candidates.count)
        guard wanted > 0 else { return [] }
        var picks = PickValidator.validate(try await ask(candidates, prefs, retry: false), candidates: candidates)
        if picks.count < wanted {
            picks = PickValidator.validate(try await ask(candidates, prefs, retry: true), candidates: candidates)
        }
        if picks.count < wanted {
            for item in candidates where !picks.contains(where: { $0.item.id == item.id }) && picks.count < wanted {
                picks.append(MenuPick(item: item, reason: MenuFilter.reasonFacts(item, prefs)))
            }
        }
        return picks
    }

    private static func ask(_ candidates: [MenuItem], _ prefs: MenuPreferences, retry: Bool) async throws -> [RawPick] {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            You help someone choose a dish from a restaurant menu. Now: \(DateText.promptNow()).
            Pick the best \(min(3, candidates.count)) dishes from the numbered list for what they want. Only pick dishes from the list, \
            by number and exact name. Never mention a dish, ingredient or price that isn't in the list. \
            Never say a dish is safe for an allergy. Best match first.\(retry ? " Use \(min(3, candidates.count)) different numbers between 1 and \(candidates.count)." : "")
            """)
        let list = candidates.enumerated().map { i, c in
            var line = "\(i + 1). \(c.name)"
            if !c.description.isEmpty { line += " - \(c.description.prefix(90))" }
            if let p = c.price { line += " ($\(MenuFilter.format(p)))" }
            return line
        }.joined(separator: "\n")
        let prompt = "They want: \(prefs.summary).\n\nMenu:\n\(list)"
        do {
            let result = try await session.respond(to: prompt, generating: RankedPicks.self, options: GenerationOptions(temperature: 0.2)).content
            return result.picks.map { RawPick(number: $0.number, name: $0.name, reason: $0.reason) }
        } catch let error as LanguageModelSession.GenerationError {
            throw ToolError(error.localizedDescription)
        }
    }
}
