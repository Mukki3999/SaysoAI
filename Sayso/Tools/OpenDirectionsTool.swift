import FoundationModels
import MapKit

struct OpenDirectionsTool: Tool {
    let collector: PlanCollector

    let name = "openDirections"
    let description = "Propose driving directions to a place. Opens in Maps once approved."

    @Generable
    struct Arguments {
        @Guide(description: "Place name or address, e.g. 'Blue Bottle Coffee' or '1 Infinite Loop'")
        var destination: String
    }

    func call(arguments a: Arguments) async throws -> String {
        guard !a.destination.isEmpty else { throw ToolError("Where do you want to go?") }
        let added = await collector.add(.directions(DirectionsDraft(destination: a.destination)))
        return added ? "Queued directions to \(a.destination) for the user to approve." : "Already queued."
    }
}

enum DirectionsAction {
    @MainActor
    static func open(_ d: DirectionsDraft) async throws {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = d.destination
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else {
            throw ToolError("I couldn't find “\(d.destination)” on the map.")
        }
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
