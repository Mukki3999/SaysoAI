import EventKit

enum CalendarAccess {
    /// Editing, cancelling and planning need to read the calendar. Asks the first time, never before.
    static func ensureFullEvents() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return
        case .denied, .restricted: throw PermissionDenied(feature: "full calendar")
        default: break
        }
        guard (try? await EKEventStore().requestFullAccessToEvents()) == true else {
            throw PermissionDenied(feature: "full calendar")
        }
    }
}
