import CoreGraphics
import Foundation

/// One line of text found in the photo. `box` is normalized (0...1) with the origin at the top left.
struct OCRLine: Identifiable, Equatable, Sendable {
    let index: Int
    var text: String
    var box: CGRect
    var id: Int { index }
}

struct MenuItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var description = ""
    var price: Double?
    var section = ""
    /// Indexes into the OCR lines this dish came from, for highlighting it on the photo.
    var lineIndexes: [Int]

    var searchText: String { "\(name) \(description)" }
}

struct MenuPick: Identifiable, Equatable, Sendable {
    var id: UUID { item.id }
    var item: MenuItem
    var reason: String
}

enum MenuPrice {
    private static let tail = try! NSRegularExpression(pattern: #"[\s/|·•–-]*([$£€])?\s?(\d{1,3}(?:[.,]\d{2})?)\s*$"#)
    private static let anywhere = try! NSRegularExpression(pattern: #"[$£€]\s?(\d{1,3}(?:[.,]\d{1,2})?)"#)
    private static let only = try! NSRegularExpression(pattern: #"^\s*[$£€]?\s?\d{1,3}(?:[.,]\d{2})?\s*$"#)

    static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    /// "Margherita .... 14 / 16" -> ("Margherita", 14). Several trailing prices (sizes) give the lowest.
    static func split(_ text: String) -> (name: String, price: Double?) {
        var rest = text.trimmingCharacters(in: .whitespaces)
        var prices: [Double] = []
        while let m = tail.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
              let numRange = Range(m.range(at: 2), in: rest), let whole = Range(m.range, in: rest) {
            let candidate = String(rest[..<whole.lowerBound])
            let hasSymbol = m.range(at: 1).location != NSNotFound
            // A bare number only counts as a price if a name is left in front of it.
            guard hasSymbol || candidate.contains(where: \.isLetter), let n = number(String(rest[numRange])) else { break }
            prices.append(n)
            rest = candidate
        }
        let name = rest.trimmingCharacters(in: CharacterSet(charactersIn: " .…·-–—:|"))
        guard !prices.isEmpty, name.contains(where: \.isLetter) else { return (text.trimmingCharacters(in: .whitespaces), nil) }
        return (name, prices.min())
    }

    /// Lowest price-like number in a line, with or without a currency symbol.
    static func find(in text: String) -> Double? {
        if let p = split(text).price { return p }
        let matches = anywhere.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { Range($0.range(at: 1), in: text).flatMap { number(String(text[$0])) } }.min()
    }

    static func isPriceOnly(_ text: String) -> Bool {
        only.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
