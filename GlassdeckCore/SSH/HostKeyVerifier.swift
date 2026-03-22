import Foundation
import Crypto
import Security

/// Manages SSH host key fingerprint verification (TOFU — Trust On First Use).
///
/// Stores known host key fingerprints in the Keychain for secure persistence.
/// On first connection to a host, the fingerprint is saved. On subsequent
/// connections, it's compared against the stored value to detect MITM attacks.
struct HostKeyVerifier: Sendable {
    private static let keychainService = "com.glassdeck.known-hosts"

    enum VerificationResult: Sendable {
        case trusted
        case newHost(fingerprint: String)
        case mismatch(expected: String, actual: String)
    }

    /// Verify a host key fingerprint against known hosts.
    static func verify(host: String, port: Int, fingerprint: String) -> VerificationResult {
        let hostKey = "\(host):\(port)"
        let knownHosts = loadKnownHosts()

        if let storedFingerprint = knownHosts[hostKey] {
            if storedFingerprint == fingerprint {
                return .trusted
            } else {
                return .mismatch(expected: storedFingerprint, actual: fingerprint)
            }
        } else {
            return .newHost(fingerprint: fingerprint)
        }
    }

    /// Trust a new host key fingerprint (TOFU).
    static func trustHost(host: String, port: Int, fingerprint: String) {
        let hostKey = "\(host):\(port)"
        var knownHosts = loadKnownHosts()
        knownHosts[hostKey] = fingerprint
        saveKnownHosts(knownHosts)
    }

    /// Remove a host from known hosts (for key rotation).
    static func forgetHost(host: String, port: Int) {
        let hostKey = "\(host):\(port)"
        var knownHosts = loadKnownHosts()
        knownHosts.removeValue(forKey: hostKey)
        saveKnownHosts(knownHosts)
    }

    /// Compute SHA-256 fingerprint from raw host key data.
    ///
    /// Returns a colon-separated hex string like:
    /// `SHA256:ab:cd:ef:12:34:...`
    static func fingerprint(from publicKeyData: Data) -> String {
        let hash = SHA256.hash(data: publicKeyData)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined(separator: ":")
        return "SHA256:\(hex)"
    }

    /// Get all known hosts and their fingerprints.
    static func allKnownHosts() -> [String: String] {
        loadKnownHosts()
    }

    // MARK: - Keychain Persistence

    private static func loadKnownHosts() -> [String: String] {
        // Try Keychain first
        if let data = loadFromKeychain(),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        // Migrate from legacy UserDefaults if present
        if let legacyData = UserDefaults.standard.data(forKey: "glassdeck.known-hosts"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: legacyData) {
            saveKnownHosts(decoded)
            UserDefaults.standard.removeObject(forKey: "glassdeck.known-hosts")
            return decoded
        }
        return [:]
    }

    private static func saveKnownHosts(_ hosts: [String: String]) {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        saveToKeychain(data)
    }

    private static func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "known-hosts",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func saveToKeychain(_ data: Data) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "known-hosts",
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "known-hosts",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
