import Foundation
import Security

/// Manages SSH keys: generation, import, and secure Keychain storage.
public final class SSHKeyManager: Sendable {
    public static let shared = SSHKeyManager()
    private init() {}

    private static let keychainService = "com.glassdeck.ssh-keys"

    /// Generate a new Ed25519 SSH key pair.
    public func generateEd25519Key(name: String) throws -> String {
        let keyID = UUID().uuidString
        let keypair = SSHAuthenticator.generateEd25519Key()
        try storePrivateKey(id: keyID, name: name, data: keypair.privateKeyData)
        return keyID
    }

    /// Import an existing SSH private key.
    public func importKey(name: String, pemData: Data) throws -> String {
        _ = try SSHAuthenticator.publicKeyString(fromPrivateKeyData: pemData)
        let keyID = UUID().uuidString
        try storePrivateKey(id: keyID, name: name, data: pemData)
        return keyID
    }

    /// Public convenience: save a key with just ID and data.
    public func savePrivateKey(id: String, keyData: Data) {
        try? storePrivateKey(id: id, name: id, data: keyData)
    }

    public func publicKeyString(id: String) throws -> String {
        guard let data = loadPrivateKey(id: id) else {
            throw KeychainError.notFound(id)
        }

        return try SSHAuthenticator.publicKeyString(fromPrivateKeyData: data)
    }

    /// Store a private key in the iOS Keychain.
    private func storePrivateKey(id: String, name: String, data: Data) throws {
        // Delete existing key with same ID first (update)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: id,
            kSecAttrLabel as String: name,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    /// Load a private key from the iOS Keychain.
    public func loadPrivateKey(id: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Delete a key from the Keychain.
    public func deleteKey(id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: id,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// List all stored SSH key IDs.
    public func listKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }
    }

    /// List all stored SSH key IDs and names.
    public func listKeysDetailed() -> [(id: String, name: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let id = item[kSecAttrAccount as String] as? String,
                  let name = item[kSecAttrLabel as String] as? String else {
                return nil
            }
            return (id: id, name: name)
        }
    }

    public enum KeychainError: Error, LocalizedError {
        case storeFailed(OSStatus)
        case deleteFailed(OSStatus)
        case notFound(String)

        public var errorDescription: String? {
            switch self {
            case .storeFailed(let status):
                return "Failed to store SSH key in Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete SSH key from Keychain (status: \(status))"
            case .notFound(let id):
                return "SSH key '\(id)' was not found in Keychain"
            }
        }
    }
}
