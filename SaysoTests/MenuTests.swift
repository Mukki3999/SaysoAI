import Testing
import Foundation
import CoreGraphics
@testable import Sayso

struct MenuTests {
    static let sample = """
    STARTERS
    Burrata & Tomato 14
    fresh burrata, heirloom tomato, basil
    Crispy Calamari 16
    lemon aioli, spicy marinara
    Soup of the Day 9
    MAINS
    Margherita Pizza 18
    tomato, mozzarella, basil (V)
    Spicy Rigatoni 19
    vodka sauce, chili flakes, parmesan
    Grilled Salmon 28
    lemon, asparagus, new potatoes
    Veggie Burger 16
    house patty, avocado, vegan bun
    Mushroom Risotto 21
    arborio rice, mushrooms, parmesan
    Roasted Chicken 24
    herbs, mashed potatoes
    Garden Salad 12
    greens, cucumber, lemon vinaigrette
    DESSERTS
    Tiramisu 10
    Chocolate Cake 9
    """

    static func lines(_ text: String) -> [OCRLine] {
        text.split(separator: "\n").enumerated().map {
            OCRLine(index: $0.offset, text: $0.element.trimmingCharacters(in: .whitespaces),
                    box: CGRect(x: 0.1, y: Double($0.offset) * 0.03, width: 0.5, height: 0.025))
        }
    }

    var items: [MenuItem] { MenuHeuristicParser.parse(Self.lines(Self.sample)) }

    func names(_ prefs: MenuPreferences, in items: [MenuItem]? = nil) -> [String] {
        MenuFilter.apply(items ?? self.items, prefs).candidates.map(\.name).sorted()
    }

    // MARK: Prices

    @Test func splitsPricesFromNames() {
        #expect(MenuPrice.split("Margherita ..... 14").name == "Margherita")
        #expect(MenuPrice.split("Margherita ..... 14").price == 14)
        #expect(MenuPrice.split("Pizza $12 / $16").price == 12)
        #expect(MenuPrice.split("Soup 9.50").price == 9.5)
        #expect(MenuPrice.split("Steak frites 12oz").price == nil)
        #expect(MenuPrice.split("Just a name").price == nil)
        #expect(MenuPrice.isPriceOnly("$14") && MenuPrice.isPriceOnly("14.50") && !MenuPrice.isPriceOnly("Tea 4"))
    }

    // MARK: OCR ordering

    @Test func joinsALonePriceOntoItsDish() {
        let lines = MenuOCRService.arrange([("Margherita", CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.03)),
                                            ("14", CGRect(x: 0.8, y: 0.205, width: 0.05, height: 0.03)),
                                            ("Calamari", CGRect(x: 0.1, y: 0.3, width: 0.25, height: 0.03))])
        #expect(lines.map(\.text) == ["Margherita 14", "Calamari"])
        #expect(lines[0].box.maxX > 0.8)
    }

    @Test func readsTwoColumnsOneAfterTheOther() {
        var raw: [(String, CGRect)] = []
        for i in 0..<5 {
            raw.append(("L\(i)", CGRect(x: 0.05, y: 0.1 + Double(i) * 0.1, width: 0.35, height: 0.04)))
            raw.append(("R\(i)", CGRect(x: 0.55, y: 0.1 + Double(i) * 0.1, width: 0.35, height: 0.04)))
        }
        let order = MenuOCRService.arrange(raw).map(\.text)
        #expect(order == ["L0", "L1", "L2", "L3", "L4", "R0", "R1", "R2", "R3", "R4"])
    }

    // MARK: Parsing

    @Test func heuristicParserFindsDishesPricesAndSections() throws {
        let items = items
        #expect(items.count == 12)
        let burrata = try #require(items.first { $0.name == "Burrata & Tomato" })
        #expect(burrata.price == 14 && burrata.section == "Starters" && burrata.description.contains("heirloom"))
        #expect(items.first { $0.name == "Tiramisu" }?.section == "Desserts")
        #expect(!items.contains { $0.name == "MAINS" })
    }

    @Test func parsesMenusWithNoPrices() {
        let text = "Margherita\ntomato, mozzarella, basil\nQuattro Formaggi\nfour cheeses, cream\nDiavola\nspicy salami, chili"
        let found = MenuHeuristicParser.parse(Self.lines(text))
        #expect(found.map(\.name) == ["Margherita", "Quattro Formaggi", "Diavola"])
        #expect(found.allSatisfy { $0.price == nil })
    }

    @Test func chunksStayInsideTheWindowAndCoverEverything() {
        let many = (0..<100).map { OCRLine(index: $0, text: "Dish number \($0) with a fairly long description here", box: .zero) }
        let chunks = MenuParser.chunks(many)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 22 && $0.reduce(0) { $0 + $1.text.count } <= 1200 })
        #expect(Set(chunks.flatMap { $0.map(\.index) }) == Set(0..<100))
    }

    @Test func dropsDishesNotPrintedOnTheirLines() {
        let source = Self.lines("Spicy Rigatoni 19\nvodka sauce")
        #expect(MenuParser.isGrounded(name: "Spicy Rigatoni", in: source))
        #expect(!MenuParser.isGrounded(name: "Lobster Thermidor", in: source))
    }

    @Test func mergesRepeatsFromOverlappingChunks() {
        let a = MenuItem(name: "Garden Salad", price: 12, lineIndexes: [3, 4])
        let b = MenuItem(name: "garden salad", description: "greens, cucumber", price: 12, lineIndexes: [4, 5])
        let merged = MenuParser.merge([a, b])
        #expect(merged.count == 1 && merged[0].lineIndexes == [3, 4, 5] && merged[0].description == "greens, cucumber")
    }

    // MARK: Filter

    @Test func vegetarianDropsMeatAndFish() {
        let n = names(.init(diet: .vegetarian))
        #expect(!n.contains("Roasted Chicken") && !n.contains("Grilled Salmon") && !n.contains("Crispy Calamari"))
        #expect(n.contains("Veggie Burger") && n.contains("Margherita Pizza") && n.contains("Mushroom Risotto"))
    }

    @Test func veganDropsDairyUnlessLabelled() {
        let n = names(.init(diet: .vegan))
        #expect(n.contains("Garden Salad") && n.contains("Veggie Burger"))
        #expect(!n.contains("Margherita Pizza") && !n.contains("Burrata & Tomato") && !n.contains("Mushroom Risotto"))
    }

    @Test func pescatarianKeepsFishDropsMeat() {
        let n = names(.init(diet: .pescatarian))
        #expect(n.contains("Grilled Salmon") && !n.contains("Roasted Chicken"))
    }

    @Test func priceCapIsHard() {
        let result = MenuFilter.apply(items, .init(maxPrice: 15))
        #expect(!result.candidates.isEmpty && result.candidates.allSatisfy { ($0.price ?? 99) <= 15 })
    }

    @Test func dessertsAndDrinksAreLeftOutUnlessAsked() {
        #expect(!names(.init()).contains("Tiramisu"))
        #expect(names(.init(course: .dessert)) == ["Chocolate Cake", "Tiramisu"])
    }

    @Test func notSpicyDropsSpicyDishes() {
        let n = names(.init(spice: .mild))
        #expect(!n.contains("Spicy Rigatoni") && !n.contains("Crispy Calamari") && n.contains("Garden Salad"))
    }

    @Test func avoidListExpandsGroups() {
        #expect(!names(.init(avoid: ["mushrooms"])).contains("Mushroom Risotto"))
        let dairyFree = names(.init(avoid: ["dairy"]))
        #expect(!dairyFree.contains("Burrata & Tomato") && !dairyFree.contains("Margherita Pizza") && dairyFree.contains("Garden Salad"))
    }

    @Test func impossibleRequestExplainsWhy() {
        let result = MenuFilter.apply(items, .init(diet: .vegan, maxPrice: 5))
        #expect(result.candidates.isEmpty)
        #expect(result.hint?.contains("Nothing is under $5") == true)
        #expect(result.hint?.contains("$9") == true)
    }

    @Test func noMatchingDietSaysSo() {
        let steak = Self.lines("Ribeye Steak 40\nBeef Burger 18\nPork Chop 30")
        let result = MenuFilter.apply(MenuHeuristicParser.parse(steak), .init(diet: .vegetarian))
        #expect(result.candidates.isEmpty && result.hint == "No vegetarian dishes found in the menu text.")
    }

    @Test func neverPassesMoreThanAboutTwentyFiveToTheModel() {
        let big = (0..<80).map { MenuItem(name: "Dish \($0)", description: "grilled fresh", price: Double($0 % 30 + 5), lineIndexes: [$0]) }
        let result = MenuFilter.apply(big, .init(mood: ["light"]))
        #expect(result.candidates.count == MenuFilter.maxCandidates && result.matched == 80)
    }

    @Test func budgetIsIgnoredWhenTheMenuHasNoPrices() {
        let free = MenuHeuristicParser.parse(Self.lines("Margherita\ntomato, mozzarella\nDiavola\nspicy salami, chili"))
        let result = MenuFilter.apply(free, .init(maxPrice: 15))
        #expect(result.candidates.count == 2 && result.budgetIgnored)
    }

    @Test func moodWordsRankLightDishesFirst() {
        let first = MenuFilter.apply(items, .init(mood: ["light"])).candidates.first?.name
        #expect(first == "Garden Salad" || first == "Soup of the Day")
    }

    // MARK: Pick validation

    @Test func validatorKeepsOnlyRealCandidates() {
        let c = [MenuItem(name: "Garden Salad", price: 12, lineIndexes: [0]), MenuItem(name: "Veggie Burger", price: 16, lineIndexes: [1]),
                 MenuItem(name: "Soup of the Day", price: 9, lineIndexes: [2])]
        let raw = [RawPick(number: 1, name: "Garden Salad", reason: "Light and fresh."),
                   RawPick(number: 2, name: "Lobster Roll", reason: "Not on the menu."),      // invented
                   RawPick(number: 9, name: "Veggie Burger", reason: "Bad number, right name."),   // number off, name valid
                   RawPick(number: 3, name: "Soup of the Day", reason: "  "),                  // empty reason
                   RawPick(number: 1, name: "Garden Salad", reason: "Duplicate."),
                   RawPick(number: 3, name: "soup of the day", reason: "Warm.")]
        let picks = PickValidator.validate(raw, candidates: c)
        #expect(picks.map(\.item.name) == ["Garden Salad", "Veggie Burger", "Soup of the Day"])
        #expect(picks[1].reason == "Bad number, right name.")
    }

    @Test func validatorRejectsANumberThatPointsAtAnotherDish() {
        let c = [MenuItem(name: "Garden Salad", lineIndexes: [0]), MenuItem(name: "Veggie Burger", lineIndexes: [1])]
        #expect(PickValidator.validate([RawPick(number: 1, name: "Veggie Burger", reason: "x")], candidates: c).map(\.item.name) == ["Veggie Burger"])
        #expect(PickValidator.validate([RawPick(number: 1, name: "Steak", reason: "x")], candidates: c).isEmpty)
    }

    // MARK: Preferences

    @Test func parsesAFullRequest() {
        let p = PreferenceParser.heuristic(.init(), "something light, vegetarian, under $20, not too spicy")
        #expect(p.diet == .vegetarian && p.maxPrice == 20 && p.spice == .mild && p.mood == ["light"] && p.avoid.isEmpty)
    }

    @Test func parsesAvoidLists() {
        let p = PreferenceParser.heuristic(.init(), "no mushrooms or olives please, and without nuts")
        #expect(p.avoid == ["mushrooms", "olives", "nuts"])
    }

    @Test func followUpsChangeOnlyWhatTheySay() {
        let start = PreferenceParser.heuristic(.init(), "light, vegetarian, under $20")
        let vegan = PreferenceParser.heuristic(start, "make it vegan")
        #expect(vegan.diet == .vegan && vegan.maxPrice == 20 && vegan.mood == ["light"])
        let dessert = PreferenceParser.heuristic(vegan, "what about dessert?")
        #expect(dessert.course == .dessert && dessert.diet == .vegan)
        let cheaper = PreferenceParser.heuristic(dessert, "under $15")
        #expect(cheaper.maxPrice == 15)
        #expect(PreferenceParser.heuristic(cheaper, "start over").isDefault)
    }

    @Test func chipsCanBeRemoved() {
        var p = PreferenceParser.heuristic(.init(), "vegan, under $12, no nuts")
        for chip in p.chips { p.remove(chip) }
        #expect(p.isDefault)
    }
}
