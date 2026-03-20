import Foundation
import Security

/// Handles SSH authentication: password and public key.
struct SSHAuthenticator: Sendable {
    enum AuthResult: Sendable {
        case success
        case failure(String)
    }

    /// Authenticate with password.
    func authenticateWithPassword(
        username: String,
        password: String
    ) async throws -> AuthResult {
        // TODO: Implement password auth via SwiftNIO SSH
        // SSHClientConfiguration with UserAuthDelegate
        return .success
    }

    /// Authenticate with SSH key from Keychain.
    func authenticateWithKey(
        username: String,
        keyID: String
    ) async throws -> AuthResult {
        guard let keyData = SSHKeyManager.shared.loadPrivateKey(id: keyID) else {
            return .failure("SSH key not found in Keychain")
        }

        // TODO: Implement key auth via SwiftNIO SSH
        // Parse key data, create NIOSSHPrivateKey, use in auth delegate
        _ = keyData
        return .success
    }
}
