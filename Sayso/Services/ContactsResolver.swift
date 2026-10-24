import Contacts

struct ResolvedContact: Sendable {
    var name: String
    var phone: String?
    var email: String?
}

enum ContactsResolver {
    /// Looks up a spoken name. Returns nil if there's no match; throws if access is denied.
    /// Numbers and email addresses pass straight through without touching Contacts.
    static func resolve(_ spoken: String) async throws -> ResolvedContact? {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return ResolvedContact(name: trimmed, phone: nil, email: trimmed) }
        if trimmed.range(of: #"^[+\d][\d\s().-]{5,}$"#, options: .regularExpression) != nil {
            return ResolvedContact(name: trimmed, phone: trimmed, email: nil)
        }
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .denied, .restricted: throw PermissionDenied(feature: "contacts")
        default: break
        }
        guard try await store.requestAccess(for: .contacts) else { throw PermissionDenied(feature: "contacts") }

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let matches = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: trimmed), keysToFetch: keys)
        // Prefer an exact full-name match, then the first.
        let best = matches.first { CNContactFormatter.string(from: $0, style: .fullName)?.lowercased() == trimmed.lowercased() }
            ?? matches.first
        guard let c = best else { return nil }
        return ResolvedContact(name: CNContactFormatter.string(from: c, style: .fullName) ?? trimmed,
                               phone: c.phoneNumbers.first?.value.stringValue,
                               email: c.emailAddresses.first.map { $0.value as String })
    }
}
