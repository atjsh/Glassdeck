import Foundation
import os
import Security

/// Abstracts Keychain operations for testability.
public protocol KeychainProvider: Sendable {
    func add(query: [String: Any]) -> OSStatus
    @discardableResult
    func delete(query: [String: Any]) -> OSStatus
    func copyMatching(query: [String: Any]) -> (OSStatus, AnyObject?)
}

/// Default implementation that delegates to the real iOS Keychain.
public struct SystemKeychainProvider: KeychainProvider {
    public init() {}

    public func add(query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    public func delete(query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }

    public func copyMatching(query: [String: Any]) -> (OSStatus, AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
}

/// Manages SSH keys: generation, import, and secure Keychain storage.
public final class SSHKeyManager: Sendable {
    public static let shared = SSHKeyManager()

    private static let logger = Logger(subsystem: "com.glassdeck", category: "SSHKeyManager")
    private let keychainProvider: KeychainProvider

    public init(keychainProvider: KeychainProvider = SystemKeychainProvider()) {
        self.keychainProvider = keychainProvider
    }

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
        do {
            try storePrivateKey(id: id, name: id, data: keyData)
        } catch {
            Self.logger.error("Failed to save private key '\(id)': \(error.localizedDescription)")
        }
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
        _ = keychainProvider.delete(query: deleteQuery)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: id,
            kSecAttrLabel as String: name,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = keychainProvider.add(query: query)
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

        let (status, result) = keychainProvider.copyMatching(query: query)
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

        let status = keychainProvider.delete(query: query)
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

        let (status, result) = keychainProvider.copyMatching(query: query)
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

        let (status, result) = keychainProvider.copyMatching(query: query)
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
