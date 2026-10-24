import Foundation

struct RecentAction: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let symbol: String
}
