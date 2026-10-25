import Foundation

/// What the user wants, as structured state. Follow-ups change this; no chat history is replayed.
struct MenuPreferences: Equatable, Sendable, Codable {
    enum Diet: String, Codable, CaseIterable, Sendable { case none, vegetarian, vegan, pescatarian }
    enum Spice: String, Codable, Sendable { case any, mild, hot }
    /// `meal` is everything except desserts and drinks.
    enum Course: String, Codable, Sendable { case meal, starter, dessert, drink }

    var diet: Diet = .none
    var avoid: [String] = []
    var maxPrice: Double?
    var spice: Spice = .any
    var mood: [String] = []
    var course: Course = .meal

    var isDefault: Bool { self == MenuPreferences() }

    /// One-line summary for prompts.
    var summary: String {
        var parts: [String] = []
        if diet != .none { parts.append("diet: \(diet.rawValue)") }
        if !avoid.isEmpty { parts.append("avoid: \(avoid.joined(separator: ", "))") }
        if let p = maxPrice { parts.append("budget: under \(Int(p))") }
        if spice != .any { parts.append(spice == .mild ? "spice: not spicy" : "spice: likes spicy") }
        if !mood.isEmpty { parts.append("mood: \(mood.joined(separator: ", "))") }
        if course != .meal { parts.append("course: \(course.rawValue)") }
        return parts.isEmpty ? "none" : parts.joined(separator: "; ")
    }
}

extension MenuPreferences {
    /// A chip shown under the input, tappable to remove.
    struct Chip: Identifiable, Equatable {
        enum Kind: Equatable { case diet, avoid(String), price, spice, mood(String), course }
        var kind: Kind
        var label: String
        var id: String { label }
    }

    var chips: [Chip] {
        var out: [Chip] = []
        if diet != .none { out.append(Chip(kind: .diet, label: diet.rawValue.capitalized)) }
        if let p = maxPrice { out.append(Chip(kind: .price, label: "Under $\(Int(p))")) }
        if spice != .any { out.append(Chip(kind: .spice, label: spice == .mild ? "Not spicy" : "Spicy")) }
        if course != .meal { out.append(Chip(kind: .course, label: course.rawValue.capitalized)) }
        out += avoid.map { Chip(kind: .avoid($0), label: "No \($0)") }
        out += mood.map { Chip(kind: .mood($0), label: $0.capitalized) }
        return out
    }

    mutating func remove(_ chip: Chip) {
        switch chip.kind {
        case .diet: diet = .none
        case .price: maxPrice = nil
        case .spice: spice = .any
        case .course: course = .meal
        case .avoid(let a): avoid.removeAll { $0 == a }
        case .mood(let m): mood.removeAll { $0 == m }
        }
    }
}
