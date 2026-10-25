import Foundation
import FoundationModels

/// Turns "something light, vegetarian, under $20, not too spicy" into `MenuPreferences`, and applies follow-ups
/// ("make it vegan", "what about dessert?") on top of the current ones.
enum PreferenceParser {
    // MARK: Model

    @Generable
    enum ParsedDiet { case none, vegetarian, vegan, pescatarian }
    @Generable
    enum ParsedSpice { case any, notSpicy, spicy }
    @Generable
    enum ParsedCourse { case meal, starter, dessert, drink }

    @Generable
    struct ParsedPreferences {
        @Guide(description: "Diet the user asked for, or none")
        var diet: ParsedDiet
        @Guide(description: "Ingredients or foods the user wants to avoid, one or two words each")
        var avoid: [String]
        @Guide(description: "Maximum price per dish as a number, only if the user gave a budget")
        var maxPrice: Double?
        var spice: ParsedSpice
        @Guide(description: "Mood words like light, hearty, healthy, comfort, fresh, filling")
        var mood: [String]
        @Guide(description: "meal for a main dish, or starter, dessert, drink only if asked")
        var course: ParsedCourse
    }

    /// The model reads the sentence; plain-Swift rules then overrule it on anything explicit (a price, a diet word).
    static func update(_ current: MenuPreferences, with text: String) async -> MenuPreferences {
        let rules = heuristic(current, text)
        guard case .available = SystemLanguageModel.default.availability else { return rules }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            You read what a diner wants to eat and update their preferences. Now: \(DateText.promptNow()).
            Current preferences: \(current.summary).
            Return the full updated preferences. Keep everything the user didn't change. \
            "Make it vegan" changes only the diet. "What about dessert?" changes only the course. \
            "Not too spicy" means notSpicy. Do not invent preferences.
            """)
        guard let parsed = try? await session.respond(to: text, generating: ParsedPreferences.self,
                                                      options: GenerationOptions(temperature: 0.1)).content else { return rules }
        var result = current
        result.diet = switch parsed.diet { case .none: current.diet; case .vegetarian: .vegetarian; case .vegan: .vegan; case .pescatarian: .pescatarian }
        result.spice = switch parsed.spice { case .any: current.spice; case .notSpicy: .mild; case .spicy: .hot }
        result.course = switch parsed.course { case .meal: current.course; case .starter: .starter; case .dessert: .dessert; case .drink: .drink }
        result.maxPrice = parsed.maxPrice.flatMap { $0 > 0 ? $0 : nil } ?? current.maxPrice
        result.avoid = unique(current.avoid + parsed.avoid.map(clean))
        result.mood = Array(unique(current.mood + parsed.mood.map(clean)).prefix(5))
        // Explicit wording always wins over the model.
        if rules.diet != current.diet { result.diet = rules.diet }
        if rules.maxPrice != current.maxPrice { result.maxPrice = rules.maxPrice }
        if rules.spice != current.spice { result.spice = rules.spice }
        if rules.course != current.course { result.course = rules.course }
        result.avoid = unique(result.avoid + rules.avoid)
        return result
    }

    // MARK: Rules (pure, tested)

    static func heuristic(_ current: MenuPreferences, _ text: String) -> MenuPreferences {
        var p = current
        let t = " " + text.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }

        if has("start over", "reset", "never mind that", "clear everything") { return MenuPreferences() }

        // Diet
        if has("vegan") { p.diet = .vegan }
        else if has("vegetarian", "veggie", "no meat", "without meat", "meatless") { p.diet = .vegetarian }
        else if has("pescatarian", "pescetarian") { p.diet = .pescatarian }
        else if has("any diet", "eat meat", "not vegetarian", "not vegan", "anything goes") { p.diet = .none }

        // Budget
        if has("any price", "no budget", "no limit", "price doesn't matter") { p.maxPrice = nil }
        let price = try! NSRegularExpression(pattern: #"(?:under|below|less than|max(?:imum)?|up to|no more than|within|at most|cheaper than|<)\s*\$?\s*(\d+(?:\.\d+)?)|\$\s*(\d+(?:\.\d+)?)\s*(?:or less|max|budget|or under|and under)"#)
        if let m = price.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
            for g in 1...2 {
                if let r = Range(m.range(at: g), in: t), let n = Double(t[r]), n > 0 { p.maxPrice = n }
            }
        }

        // Spice
        if has("not too spicy", "not spicy", "mild", "no spice", "not hot", "nothing spicy", "no heat", "not very spicy", "isn't spicy") { p.spice = .mild }
        else if has("spicy", "fiery", "with a kick", "extra hot") { p.spice = .hot }

        // Course
        if has("dessert", "something sweet", "sweet treat") { p.course = .dessert }
        else if has("drink", "cocktail", "wine", "beer", "coffee") { p.course = .drink }
        else if has("starter", "appetizer", "small plate") { p.course = .starter }
        else if has("main", "entree", "entrée", "dinner", "lunch", "something to eat", "meal") { p.course = .meal }

        // Avoid list: "no mushrooms", "without nuts", "allergic to shellfish", "avoid dairy"
        let avoid = try! NSRegularExpression(pattern: #"(?:\bno\b|\bwithout\b|\bavoid\b|allergic to|\bhate\b|can't eat|cannot eat|\bskip\b|\bnot\b)\s+([a-z' ,]+?)(?=[.;!?]|\bunder\b|\bbelow\b|\bbut\b|\bwith\b|\$|\d|$)"#)
        let skip: Set<String> = ["meat", "spicy", "too", "very", "spice", "heat", "hot", "too spicy", "very spicy", "a", "the", "too much", "much", "something", "anything", "mild", "dairy-free", "vegetarian", "vegan"]
        for m in avoid.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
            guard let r = Range(m.range(at: 1), in: t) else { continue }
            var phrase = String(t[r])
            for filler in [" please", " thanks", " thank you", " though", " for me"] { phrase = phrase.replacingOccurrences(of: filler, with: "") }
            phrase = phrase.replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: " or ", with: ",")
            for raw in phrase.split(separator: ",") {
                var word = clean(String(raw))
                for lead in ["too ", "very ", "a ", "any ", "much ", "without ", "no ", "avoid ", "and "] where word.hasPrefix(lead) { word = String(word.dropFirst(lead.count)) }
                if word.isEmpty || skip.contains(word) || word.split(separator: " ").count > 2 { continue }
                p.avoid.append(word)
            }
        }
        p.avoid = unique(p.avoid)

        // Mood
        let moods = ["light", "hearty", "filling", "healthy", "fresh", "comfort", "rich", "indulgent", "protein", "crispy", "creamy", "simple", "cozy"]
        for m in moods where t.range(of: "\\b\(m)\\b", options: .regularExpression) != nil && !p.mood.contains(m) { p.mood.append(m) }
        p.mood = Array(p.mood.suffix(5))
        return p
    }

    private static func clean(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
