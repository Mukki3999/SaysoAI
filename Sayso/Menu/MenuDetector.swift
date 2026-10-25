import Foundation

/// Decides whether a photo is a menu, so it can go to the Menu Helper instead of the calendar.
enum MenuDetector {
    private static let foodWords = ["eat", "menu", "dish", "hungry", "order", "vegetarian", "vegan", "dinner", "lunch", "food", "recommend", "dessert", "spicy"]

    static func looksLikeMenu(_ lines: [OCRLine], userText: String) -> Bool {
        let priced = lines.filter { MenuPrice.split($0.text).price != nil }.count
        let t = userText.lowercased()
        let askedAboutFood = foodWords.contains { t.contains($0) }
        return priced >= 5 || (priced >= 3 && askedAboutFood) || (askedAboutFood && lines.count >= 8 && priced >= 1)
    }
}
