import Foundation

/// Hard constraints in plain Swift: diet, avoid-list, price cap, spice, course. The model only ever sees
/// what survives this, capped to about 25 dishes.
enum MenuFilter {
    struct Outcome: Equatable {
        var candidates: [MenuItem]
        /// How many dishes passed before the cap was applied.
        var matched: Int
        /// Why nothing matched, when nothing did.
        var hint: String?
        /// Set when the menu shows no prices, so a budget could not be applied.
        var budgetIgnored = false
    }

    static let maxCandidates = 25

    // MARK: Word lists

    static let meat: Set<String> = ["beef", "steak", "pork", "bacon", "ham", "sausage", "chicken", "turkey", "duck", "lamb", "veal",
        "prosciutto", "salami", "pepperoni", "chorizo", "brisket", "rib", "meatball", "pancetta", "guanciale", "mortadella",
        "bolognese", "carnitas", "gyro", "kebab", "hot dog", "sirloin", "ribeye", "filet", "tenderloin", "venison", "bratwurst",
        "lardon", "wing", "oxtail", "short rib", "pulled pork", "ragu", "pastrami", "burger"]
    static let fish: Set<String> = ["fish", "salmon", "tuna", "shrimp", "prawn", "crab", "lobster", "scallop", "oyster", "clam",
        "mussel", "calamari", "squid", "octopus", "anchovy", "cod", "halibut", "trout", "sea bass", "snapper", "mahi", "sashimi",
        "sushi", "haddock", "swordfish", "eel", "caviar", "ceviche"]
    static let animalProducts: Set<String> = ["cheese", "mozzarella", "parmesan", "parmigiano", "cheddar", "feta", "goat cheese",
        "burrata", "ricotta", "cream", "creamy", "butter", "milk", "yogurt", "yoghurt", "egg", "mayo", "aioli", "honey", "gelato",
        "custard", "gruyere", "brie", "paneer", "ghee", "mascarpone", "gorgonzola", "provolone", "halloumi", "carbonara",
        "ice cream", "whipped", "bechamel", "alfredo"]
    static let spicy: Set<String> = ["spicy", "hot", "jalapeno", "chili", "chilli", "sriracha", "habanero", "cayenne", "harissa",
        "diablo", "arrabbiata", "buffalo", "vindaloo", "szechuan", "sichuan", "chipotle", "fiery", "peppery", "gochujang", "🌶"]
    static let dessertWords: Set<String> = ["cake", "ice cream", "gelato", "tiramisu", "cheesecake", "brownie", "sundae", "panna cotta",
        "cookie", "mousse", "flan", "churro", "sorbet", "pudding", "creme brulee", "cannoli", "baklava", "macaron", "tart", "donut"]
    static let drinkWords: Set<String> = ["latte", "espresso", "cappuccino", "lemonade", "soda", "beer", "wine", "margarita", "mojito",
        "smoothie", "cocktail", "juice", "kombucha", "tea", "coffee", "ale", "lager", "spritz", "mocktail", "cola"]

    /// Words people use in an avoid list that stand for a group of ingredients.
    static let avoidGroups: [String: Set<String>] = [
        "dairy": ["cheese", "cream", "butter", "milk", "yogurt", "yoghurt", "mozzarella", "parmesan", "ricotta", "burrata", "feta", "mascarpone", "gelato", "ice cream"],
        "gluten": ["bread", "pasta", "flour", "noodle", "bun", "wheat", "pizza", "crust", "breaded", "toast", "tortilla", "couscous", "gnocchi", "naan", "pita"],
        "nuts": ["peanut", "almond", "walnut", "cashew", "pecan", "pistachio", "hazelnut", "pine nut", "pesto", "nut"],
        "shellfish": ["shrimp", "prawn", "crab", "lobster", "scallop", "oyster", "clam", "mussel", "calamari", "squid"],
        "seafood": fish, "fish": fish, "meat": meat, "eggs": ["egg", "aioli", "mayo", "carbonara"], "egg": ["egg", "aioli", "mayo", "carbonara"],
        "pork": ["pork", "bacon", "ham", "prosciutto", "pancetta", "guanciale", "sausage", "chorizo", "salami", "pepperoni", "lardon"],
        "beef": ["beef", "steak", "brisket", "sirloin", "ribeye", "filet", "meatball", "burger", "short rib"],
        "mushrooms": ["mushroom", "shiitake", "portobello", "porcini", "cremini"], "onions": ["onion", "shallot", "scallion"],
        "garlic": ["garlic", "aioli"], "cilantro": ["cilantro", "coriander"], "alcohol": ["wine", "beer", "vodka", "rum", "whiskey", "liqueur", "bourbon"]
    ]

    // MARK: Text matching

    /// Lowercased words plus a joined string, so "pine nut" and "mushrooms" both match.
    struct Words {
        let set: Set<String>
        let joined: String

        init(_ text: String) {
            let lowered = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            let tokens = lowered.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            var all = Set(tokens)
            for t in tokens {
                if t.hasSuffix("ies") { all.insert(String(t.dropLast(3)) + "y") }
                if t.hasSuffix("es") { all.insert(String(t.dropLast(2))) }
                if t.hasSuffix("s") { all.insert(String(t.dropLast())) }
            }
            set = all
            joined = " " + tokens.joined(separator: " ") + " "
            hasChili = text.contains("🌶")
        }

        let hasChili: Bool

        func has(_ term: String) -> Bool {
            term == "🌶" ? hasChili : (term.contains(" ") ? joined.contains(" \(term)") : set.contains(term))
        }

        func hasAny(_ terms: some Sequence<String>) -> Bool { terms.contains { has($0) } }
    }

    // MARK: Classification

    static func course(of item: MenuItem) -> MenuPreferences.Course {
        let section = Words(item.section)
        let name = Words(item.name)
        if section.hasAny(["dessert", "sweet", "pudding", "sweets"]) || name.hasAny(dessertWords) { return .dessert }
        if section.hasAny(["drink", "beverage", "wine", "beer", "cocktail", "coffee", "tea", "juice", "soda", "spirits"])
            || name.hasAny(drinkWords) { return .drink }
        if section.hasAny(["starter", "appetizer", "small plates", "small plate", "to share", "snacks", "tapas"]) { return .starter }
        return .meal
    }

    /// Explicit labels such as "(V)", "vegan" or "vegetarian" printed next to a dish.
    private static func tags(_ item: MenuItem) -> (vegan: Bool, vegetarian: Bool) {
        let t = item.searchText.lowercased()
        let vegan = t.contains("vegan") || t.contains("(vg)") || t.contains("(ve)") || t.contains("plant-based") || t.contains("plant based")
        let veg = vegan || t.contains("vegetarian") || t.contains("veggie") || t.contains("(v)") || t.contains(" v)")
        return (vegan, veg)
    }

    static func passesDiet(_ item: MenuItem, _ diet: MenuPreferences.Diet) -> Bool {
        guard diet != .none else { return true }
        let tag = tags(item)
        let words = Words(item.searchText)
        // "Veggie burger" must not trip the meat list.
        let meatHit = words.hasAny(tag.vegetarian ? meat.subtracting(["burger"]) : meat)
        switch diet {
        case .none: return true
        case .pescatarian: return !meatHit
        case .vegetarian: return !meatHit && !words.hasAny(fish)
        case .vegan: return tag.vegan || (!meatHit && !words.hasAny(fish) && !words.hasAny(animalProducts))
        }
    }

    static func avoidTerms(_ words: [String]) -> Set<String> {
        var out: Set<String> = []
        for w in words {
            let key = w.lowercased().trimmingCharacters(in: .whitespaces)
            if let group = avoidGroups[key] ?? avoidGroups[key + "s"] { out.formUnion(group) } else if !key.isEmpty { out.insert(key) }
        }
        return out
    }

    static func courseMatches(_ item: MenuItem, _ wanted: MenuPreferences.Course) -> Bool {
        let c = course(of: item)
        switch wanted {
        case .meal: return c == .meal || c == .starter
        default: return c == wanted
        }
    }

    static func isSpicy(_ item: MenuItem) -> Bool {
        let text = item.searchText.lowercased()
        let words = Words(item.searchText)
        var hits = words.hasAny(spicy.subtracting(["hot"]))
        if words.has("hot"), !["hot dog", "hot fudge", "hot chocolate", "hot tea", "hot coffee", "hot cocoa"].contains(where: text.contains) { hits = true }
        return hits
    }

    // MARK: Filtering

    static func apply(_ items: [MenuItem], _ prefs: MenuPreferences, limit: Int = maxCandidates) -> Outcome {
        let menuHasPrices = items.contains { $0.price != nil }
        let avoid = avoidTerms(prefs.avoid)
        var pool = items
        var hint: String?

        func stage(_ message: @autoclosure () -> String, _ keep: (MenuItem) -> Bool) {
            guard hint == nil else { return }
            let before = pool
            pool = pool.filter(keep)
            if pool.isEmpty && !before.isEmpty { hint = message() }
        }

        stage("Nothing on this menu looks like a \(prefs.course == .meal ? "main dish" : prefs.course.rawValue).") { courseMatches($0, prefs.course) }
        stage("No \(prefs.diet.rawValue) dishes found in the menu text.") { passesDiet($0, prefs.diet) }
        stage("Everything left has \(prefs.avoid.joined(separator: " or ")) in the menu text.") { item in
            avoid.isEmpty || !Words(item.searchText).hasAny(avoid)
        }
        if prefs.spice == .mild { stage("Everything left looks spicy.") { !isSpicy($0) } }
        var budgetIgnored = false
        if let cap = prefs.maxPrice {
            if menuHasPrices {
                let cheapest = pool.compactMap(\.price).min()
                stage("Nothing is under $\(Int(cap)).\(cheapest.map { " The cheapest match is $\(format($0))." } ?? "")") { ($0.price ?? .infinity) <= cap }
            } else {
                budgetIgnored = true   // no prices printed, so a budget can't be checked
            }
        }
        if hint == nil, pool.isEmpty { hint = "Nothing matches that." }

        let ranked = pool.enumerated().sorted {
            let a = score($0.element, prefs), b = score($1.element, prefs)
            return a != b ? a > b : $0.offset < $1.offset
        }.map(\.element)
        return Outcome(candidates: Array(ranked.prefix(limit)), matched: pool.count, hint: hint, budgetIgnored: budgetIgnored && !pool.isEmpty)
    }

    private static let moodWords: [String: (like: Set<String>, dislike: Set<String>)] = [
        "light": (["salad", "soup", "grilled", "steamed", "fresh", "lemon", "broth", "vegetable", "greens", "poached", "citrus", "raw"],
                  ["fried", "cream", "creamy", "bacon", "loaded", "butter", "buttery", "cheese", "crispy", "battered"]),
        "healthy": (["salad", "grilled", "quinoa", "bowl", "vegetable", "steamed", "greens", "lentil", "avocado"], ["fried", "creamy", "bacon", "loaded"]),
        "fresh": (["salad", "citrus", "herb", "herbs", "raw", "lemon", "greens"], []),
        "hearty": (["burger", "steak", "pasta", "stew", "roast", "pork", "lamb", "loaded", "pizza", "brisket", "short rib"], ["salad"]),
        "filling": (["burger", "steak", "pasta", "stew", "roast", "loaded", "pizza", "rice", "potato"], ["salad"]),
        "comfort": (["pasta", "mac", "soup", "stew", "pie", "mashed", "burger", "lasagna", "grilled cheese", "risotto"], []),
        "rich": (["cream", "creamy", "butter", "cheese", "truffle"], [])
    ]

    /// Higher is a better fit. Used to choose which 25 dishes the model sees.
    static func score(_ item: MenuItem, _ prefs: MenuPreferences) -> Int {
        let words = Words(item.searchText)
        var s = 0
        for m in prefs.mood {
            if let list = moodWords[m] {
                s += 2 * list.like.filter { words.has($0) }.count
                s -= 2 * list.dislike.filter { words.has($0) }.count
            } else if words.has(m) { s += 3 }
        }
        if prefs.diet != .none, tags(item).vegetarian { s += 1 }
        if prefs.spice == .hot, isSpicy(item) { s += 2 }
        if item.price != nil { s += 1 }       // dishes with a price are better parsed
        if !item.description.isEmpty { s += 1 }
        return s
    }

    /// A plain description of why a dish fits, built only from facts. Used when the model's pick needs a fallback.
    static func reasonFacts(_ item: MenuItem, _ prefs: MenuPreferences) -> String {
        var parts: [String] = []
        if prefs.diet != .none { parts.append(tags(item).vegetarian ? "Labelled \(prefs.diet.rawValue)" : "No \(prefs.diet == .vegan ? "animal products" : "meat") in the menu text") }
        if let cap = prefs.maxPrice, let p = item.price, p <= cap { parts.append("under $\(Int(cap))") }
        if prefs.spice == .mild, !isSpicy(item) { parts.append("not marked spicy") }
        let words = Words(item.searchText)
        for m in prefs.mood where words.hasAny(moodWords[m]?.like ?? [m]) { parts.append("fits \"\(m)\""); break }
        guard !parts.isEmpty else { return "Fits what you asked for." }
        let line = parts.joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst() + "."
    }

    static func format(_ price: Double) -> String {
        price.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(price)) : String(format: "%.2f", price)
    }
}
