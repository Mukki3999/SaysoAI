import Foundation
import FoundationModels

struct DraftMessageTool: Tool {
    let collector: PlanCollector

    let name = "draftMessage"
    let description = "Propose a text message draft to a person. The user reviews and taps Send themselves."

    @Generable
    struct Arguments {
        @Guide(description: "Who to text: a name from the user's contacts, or a phone number")
        var recipient: String
        @Guide(description: "The message text, in the user's voice")
        var body: String
    }

    func call(arguments a: Arguments) async throws -> String {
        guard !a.recipient.isEmpty else { throw ToolError("Who should I text?") }
        let added = await collector.add(.message(MessageDraft(recipient: a.recipient, body: a.body)))
        return added ? "Queued a message draft to \(a.recipient) for the user to approve." : "Already queued."
    }
}

/// What the composer needs, after the recipient has been looked up.
struct MessageComposeRequest: Identifiable {
    let id = UUID()
    var recipients: [String]
    var body: String
}

enum MessageAction {
    static func prepare(_ d: MessageDraft) async throws -> MessageComposeRequest {
        guard let contact = try await ContactsResolver.resolve(d.recipient) else {
            throw ToolError("I couldn't find “\(d.recipient)” in your contacts.")
        }
        guard let phone = contact.phone else { throw ToolError("\(contact.name) has no phone number.") }
        return MessageComposeRequest(recipients: [phone], body: d.body)
    }
}
