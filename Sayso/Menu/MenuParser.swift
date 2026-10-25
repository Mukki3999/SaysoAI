import Foundation
import FoundationModels

/// Turns OCR lines into dishes. The model does it in small chunks; every dish it returns must be grounded in the
/// lines it points at, or it is dropped. A plain-Swift parser covers devices without Apple Intelligence.
enum MenuParser {
    // MARK: Chunking (pure)

    /// Keeps each model call well inside the 4,096-token window shared by input and output.
    static func chunks(_ lines: [OCRLine], maxLines: Int = 22, maxChars: Int = 1100, overlap: Int = 2) -> [[OCRLine]] {
        var out: [[OCRLine]] = []
        var current: [OCRLine] = []
        var chars = 0
        for line in lines {
            if !current.isEmpty, current.count >= maxLines || chars + line.text.count > maxChars {
                out.append(current)
                current = Array(current.suffix(overlap))   // a dish can straddle a boundary
                chars = current.reduce(0) { $0 + $1.text.count }
            }
            current.append(line)
            chars += line.text.count
        }
        if current.count > (out.isEmpty ? 0 : overlap) { out.append(current) }
        return out
    }

    // MARK: Model parsing

    @Generable
    struct ParsedDish {
        @Guide(description: "The dish name exactly as printed, without the price")
        var name: String
        @Guide(description: "Its printed description or ingredients. Empty if none")
        var description: String
        @Guide(description: "The numbers in square brackets of every line that belongs to this dish")
        var lines: [Int]
    }

    @Generable
    struct ParsedChunk {
        var dishes: [ParsedDish]
    }

    static func parse(_ lines: [OCRLine]) async throws -> [MenuItem] {
        var all: [MenuItem] = []
        var section = ""
        for chunk in chunks(lines) {
            let found = try await parseChunk(chunk, section: section)
            if let last = found.last(where: { !$0.section.isEmpty }) { section = last.section }
            all += found
        }
        return merge(all)
    }

    private static func parseChunk(_ chunk: [OCRLine], section: String) async throws -> [MenuItem] {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            You read one part of a restaurant menu that was scanned from a photo. Now: \(DateText.promptNow()).
            List only the dishes and drinks that appear. Skip section headings, the restaurant name, addresses, hours and notes.
            Use only the text shown. Never add a dish. Do not include prices in the name.
            """)
        let prompt = chunk.map { "[\($0.index)] \($0.text)" }.joined(separator: "\n")
        let response: ParsedChunk
        do {
            response = try await session.respond(to: prompt, generating: ParsedChunk.self, options: GenerationOptions(temperature: 0.1)).content
        } catch let error as LanguageModelSession.GenerationError {
            throw ToolError(error.localizedDescription)
        }
        let byIndex = Dictionary(uniqueKeysWithValues: chunk.map { ($0.index, $0) })
        var current = section
        // Section headings come from the lines (they have no price and are not part of a dish).
        let headings = Dictionary(uniqueKeysWithValues: chunk.compactMap { l in MenuHeuristicParser.isHeading(l.text) ? (l.index, l.text.capitalized) : nil })
        return response.dishes.compactMap { dish in
            let used = dish.lines.filter { byIndex[$0] != nil }.sorted()
            guard !used.isEmpty else { return nil }
            let source = used.compactMap { byIndex[$0] }
            guard isGrounded(name: dish.name, in: source) else { return nil }
            if let h = headings.filter({ $0.key < used[0] }).max(by: { $0.key < $1.key }) { current = h.value }
            let price = source.compactMap { MenuPrice.find(in: $0.text) }.min()
            return MenuItem(name: dish.name.trimmingCharacters(in: .whitespaces),
                            description: dish.description.trimmingCharacters(in: .whitespaces),
                            price: price, section: current, lineIndexes: used)
        }
    }

    /// A dish is real only if its name's words are printed on the lines it points at.
    static func isGrounded(name: String, in lines: [OCRLine]) -> Bool {
        let printed = normalize(lines.map(\.text).joined(separator: " "))
        let words = normalize(name).split(separator: " ").filter { $0.count >= 3 }
        guard !words.isEmpty else { return false }
        let hits = words.filter { printed.contains($0) }.count
        return Double(hits) / Double(words.count) >= 0.6
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Joins chunks and drops repeats from the overlap.
    static func merge(_ items: [MenuItem]) -> [MenuItem] {
        var out: [MenuItem] = []
        for item in items {
            let key = normalize(item.name)
            if let i = out.firstIndex(where: { normalize($0.name) == key && ($0.price == item.price || $0.price == nil || item.price == nil) }) {
                out[i].lineIndexes = Array(Set(out[i].lineIndexes + item.lineIndexes)).sorted()
                if item.description.count > out[i].description.count { out[i].description = item.description }
                if out[i].price == nil { out[i].price = item.price }
                if out[i].section.isEmpty { out[i].section = item.section }
            } else {
                out.append(item)
            }
        }
        return out
    }
}

// MARK: - Plain-Swift parser (fallback, and a cross-check)

enum MenuHeuristicParser {
    private static let headingWords: Set<String> = [
        "appetizers", "appetizer", "starters", "starter", "mains", "main", "entrees", "entree", "desserts", "dessert", "drinks",
        "beverages", "sides", "salads", "soups", "pasta", "pizza", "sandwiches", "brunch", "lunch", "dinner", "breakfast", "kids",
        "specials", "small plates", "cocktails", "wine", "beer", "burgers"
    ]

    static func isHeading(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count <= 30, MenuPrice.find(in: t) == nil else { return false }
        if headingWords.contains(t.lowercased()) { return true }
        let letters = t.filter(\.isLetter)
        return letters.count >= 4 && letters == letters.uppercased() && t.split(separator: " ").count <= 4
    }

    static func parse(_ lines: [OCRLine]) -> [MenuItem] {
        var items: [MenuItem] = []
        var section = ""
        var current: MenuItem?

        func flush() {
            if let c = current { items.append(c) }
            current = nil
        }

        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if isHeading(text) { flush(); section = text.capitalized; continue }
            if MenuPrice.isPriceOnly(text) {
                if current?.price == nil, let n = MenuPrice.find(in: text) ?? MenuPrice.number(text.filter { $0.isNumber || $0 == "." || $0 == "," }) {
                    current?.price = n
                    current?.lineIndexes.append(line.index)
                }
                continue
            }
            let (name, price) = MenuPrice.split(text)
            if price != nil {
                flush()
                current = MenuItem(name: name, price: price, section: section, lineIndexes: [line.index])
            } else if var c = current, looksLikeDescription(text, after: c) {
                c.description += (c.description.isEmpty ? "" : " ") + text
                c.lineIndexes.append(line.index)
                current = c
            } else if text.count >= 3, text.contains(where: \.isLetter) {
                flush()
                current = MenuItem(name: text, section: section, lineIndexes: [line.index])   // menus without prices
            }
        }
        flush()
        return items
    }

    private static func looksLikeDescription(_ text: String, after item: MenuItem) -> Bool {
        guard let first = text.first else { return false }
        if first.isLowercase { return true }
        if text.contains(","), text.split(separator: " ").count >= 3 { return true }
        return false
    }
}
