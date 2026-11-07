import Contacts

struct ResolvedContact: Sendable, Identifiable {
    var name: String
    var phone: String?
    var email: String?
    var id: String { name + (phone ?? "") + (email ?? "") }
}

enum ContactLookup {
    case one(ResolvedContact)
    case many([ResolvedContact])   // several people, or close-sounding names to confirm
    case none
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

    /// Like resolve, but says when it isn't sure, so the app can ask which contact was meant.
    /// Speech often mishears names ("Unkit" for "Ankit"), so a miss falls back to close-sounding names.
    static func lookup(_ spoken: String) async throws -> ContactLookup {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return .one(ResolvedContact(name: trimmed, phone: nil, email: trimmed)) }
        if trimmed.range(of: #"^[+\d][\d\s().-]{5,}$"#, options: .regularExpression) != nil {
            return .one(ResolvedContact(name: trimmed, phone: trimmed, email: nil))
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
        func resolved(_ c: CNContact) -> ResolvedContact {
            let mobile = c.phoneNumbers.first { ($0.label ?? "").lowercased().contains("mobile") || ($0.label ?? "").lowercased().contains("iphone") }
            return ResolvedContact(name: CNContactFormatter.string(from: c, style: .fullName) ?? trimmed,
                                   phone: (mobile ?? c.phoneNumbers.first)?.value.stringValue,
                                   email: c.emailAddresses.first.map { $0.value as String })
        }
        let lowered = trimmed.lowercased()
        let matches = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: trimmed), keysToFetch: keys)
        if !matches.isEmpty {
            let exact = matches.filter { CNContactFormatter.string(from: $0, style: .fullName)?.lowercased() == lowered }
            if exact.count == 1 { return .one(resolved(exact[0])) }
            if matches.count == 1 { return .one(resolved(matches[0])) }
            return .many(matches.prefix(6).map(resolved))
        }

        let spokenWords = lowered.split(separator: " ").map(String.init)
        guard let first = spokenWords.first, first.count >= 3 else { return .none }
        var all: [CNContact] = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in all.append(c) }
        let limit = first.count >= 6 ? 2 : 1
        let close = all.compactMap { c -> (CNContact, Int)? in
            let names = [c.givenName, c.familyName].map { $0.lowercased() }.filter { !$0.isEmpty }
            guard let d = names.map({ editDistance($0, first) }).min(), d <= limit else { return nil }
            return (c, d)
        }.sorted { $0.1 < $1.1 }
        return close.isEmpty ? .none : .many(close.prefix(4).map { resolved($0.0) })
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
