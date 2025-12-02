import Foundation
import Contacts

struct Contact {
    let phoneNumbers: [String]
    let displayName: String
}

protocol ContactsService {
    func requestPermission() async -> Bool
    func fetchContacts() async throws -> [Contact]
}

final class SystemContactsService: ContactsService {
    private let contactStore = CNContactStore()
    
    func requestPermission() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            do {
                return try await contactStore.requestAccess(for: .contacts)
            } catch {
                return false
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    func fetchContacts() async throws -> [Contact] {
        guard await requestPermission() else {
            throw NSError(domain: "ContactsService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"])
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [Contact] = []
        
        try contactStore.enumerateContacts(with: request) { contact, stop in
            // Get display name
            let displayName: String
            if !contact.givenName.isEmpty || !contact.familyName.isEmpty {
                displayName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            } else if !contact.nickname.isEmpty {
                displayName = contact.nickname
            } else {
                displayName = "Unknown"
            }
            
            // Get phone numbers (normalized)
            let phoneNumbers = contact.phoneNumbers.compactMap { phoneNumber -> String? in
                let number = phoneNumber.value.stringValue
                return normalizePhoneNumber(number)
            }
            
            // Only include contacts with phone numbers
            if !phoneNumbers.isEmpty {
                contacts.append(Contact(
                    phoneNumbers: phoneNumbers,
                    displayName: displayName
                ))
            }
        }
        
        return contacts
    }
    
    // MARK: - Phone Number Normalization
    
    private func normalizePhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-digit characters
        let digitsOnly = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Handle country codes
        // For US numbers, if it starts with 1 and has 11 digits, remove the 1
        if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return String(digitsOnly.dropFirst())
        }
        
        // For international numbers, keep as is (you may want to add more normalization logic)
        return digitsOnly
    }
}
