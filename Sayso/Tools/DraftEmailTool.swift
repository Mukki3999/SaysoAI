import Foundation
import FoundationModels

struct DraftEmailTool: Tool {
    let collector: PlanCollector

    let name = "draftEmail"
    let description = "Propose an email draft to a person. The user reviews and taps Send themselves."

    @Generable
    struct Arguments {
        @Guide(description: "Who to email: a name from the user's contacts, or an email address")
        var recipient: String
        @Guide(description: "Short subject line")
        var subject: String
        @Guide(description: "The email body, in the user's voice")
        var body: String
    }

    func call(arguments a: Arguments) async throws -> String {
        guard !a.recipient.isEmpty else { throw ToolError("Who should I email?") }
        let added = await collector.add(.email(EmailDraft(recipient: a.recipient, subject: a.subject, body: a.body)))
        return added ? "Queued an email draft to \(a.recipient) for the user to approve." : "Already queued."
    }
}

struct EmailComposeRequest: Identifiable {
    let id = UUID()
    var recipients: [String]
    var subject: String
    var body: String
}

enum EmailAction {
    static func prepare(_ d: EmailDraft) async throws -> EmailComposeRequest {
        guard let contact = try await ContactsResolver.resolve(d.recipient) else {
            throw ToolError("I couldn't find “\(d.recipient)” in your contacts.")
        }
        guard let email = contact.email else { throw ToolError("\(contact.name) has no email address.") }
        return EmailComposeRequest(recipients: [email], subject: d.subject, body: d.body)
    }
}
