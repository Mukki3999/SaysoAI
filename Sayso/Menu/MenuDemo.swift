#if DEBUG
import UIKit

/// Simulator-only: draws a sample menu into an image and runs the real OCR on it.
enum DemoMenu {

    @MainActor
    static func loadIfRequested(_ model: MenuHelperViewModel) async {
        guard ProcessInfo.processInfo.environment["SAYSO_DEMO_MENU"] != nil, model.image == nil else { return }
        let lines = ["STARTERS", "Burrata & Tomato  14", "fresh burrata, heirloom tomato, basil", "Crispy Calamari  16",
                     "lemon aioli, spicy marinara", "Soup of the Day  9", "MAINS", "Margherita Pizza  18", "tomato, mozzarella, basil (V)",
                     "Spicy Rigatoni  19", "vodka sauce, chili flakes, parmesan", "Grilled Salmon  28", "lemon, asparagus, new potatoes",
                     "Veggie Burger  16", "house patty, avocado, vegan bun", "Garden Salad  12", "greens, cucumber, lemon vinaigrette",
                     "DESSERTS", "Tiramisu  10"]
        let size = CGSize(width: 900, height: 1300)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for (i, line) in lines.enumerated() {
                let heading = line == line.uppercased()
                let font = UIFont.systemFont(ofSize: heading ? 34 : 30, weight: heading ? .bold : .regular)
                (line as NSString).draw(at: CGPoint(x: 60, y: 60 + CGFloat(i) * 64), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
        }
        if let data = image.jpegData(compressionQuality: 0.9) { await model.load(data) }
        if let pick = ProcessInfo.processInfo.environment["SAYSO_DEMO_MENU_SELECT"], let item = model.items.first(where: { $0.name == pick }) { model.select(item) }
        if let ask = ProcessInfo.processInfo.environment["SAYSO_DEMO_MENU_ASK"], !ask.isEmpty { await model.submit(ask) }
    }
}
#endif
