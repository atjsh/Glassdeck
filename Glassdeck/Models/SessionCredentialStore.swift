import Foundation
import Security

protocol SessionCredentialStoring: AnyObject {
    func storePassword(_ password: String, for profileID: UUID) throws
    func password(for profileID: UUID) -> String?
    func deletePassword(for profileID: UUID) throws
    func removeAll()
}

final class SessionCredentialStore: SessionCredentialStoring {
    private static let defaultKeychainService = "com.glassdeck.session-credentials"
    private let keychainService: String

    init(service: String = defaultKeychainService) {
        self.keychainService = service
    }

    func storePassword(_ password: String, for profileID: UUID) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID.uuidString,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.storeFailed(status)
        }
    }

    func password(for profileID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID.uuidString,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return password
    }

    func deletePassword(for profileID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID.uuidString,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status)
        }
    }

    func removeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum CredentialStoreError: Error, LocalizedError {
        case storeFailed(OSStatus)
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .storeFailed(let status):
                return "Failed to store SSH session credential in Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete SSH session credential from Keychain (status: \(status))"
            }
        }
    }
}
