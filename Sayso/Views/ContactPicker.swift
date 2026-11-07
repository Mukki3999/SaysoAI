import Contacts
import ContactsUI
import SwiftUI

/// The system contact picker. It runs outside the app, so it needs no Contacts permission.
struct ContactPicker: UIViewControllerRepresentable {
    enum Kind { case phone, email }
    let kind: Kind
    let onPick: (ResolvedContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [kind == .phone ? CNContactPhoneNumbersKey : CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(format: kind == .phone ? "phoneNumbers.@count > 0" : "emailAddresses.@count > 0")
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (ResolvedContact) -> Void
        init(onPick: @escaping (ResolvedContact) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            let name = CNContactFormatter.string(from: property.contact, style: .fullName) ?? ""
            if let number = property.value as? CNPhoneNumber {
                onPick(ResolvedContact(name: name, phone: number.stringValue, email: nil))
            } else if let email = property.value as? String {
                onPick(ResolvedContact(name: name, phone: nil, email: email))
            }
        }
    }
}
