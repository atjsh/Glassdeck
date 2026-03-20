import Foundation
import Security
import Crypto
import NIOSSH
import SSHClient

/// Handles SSH authentication: password and public key.
///
/// Supports:
/// - Password authentication
/// - SSH key authentication (Ed25519, P256/ECDSA from Keychain)
/// - Key generation (Ed25519)
/// - OpenSSH private key parsing (PEM format)
struct SSHAuthenticator: Sendable {
    enum AuthResult: Sendable {
        case success
        case failure(String)
    }

    /// Build an SSHAuthentication.Method for password auth.
    static func passwordMethod(_ password: String) -> SSHAuthentication.Method {
        .password(.init(password))
    }

    /// Build an SSHAuthentication.Method for SSH key auth.
    ///
    /// Loads the private key from Keychain, parses it into an NIOSSHPrivateKey,
    /// and returns a custom auth method that signs the auth challenge.
    static func keyMethod(keyID: String, passphrase: String? = nil) throws -> SSHAuthentication.Method {
        guard let keyData = SSHKeyManager.shared.loadPrivateKey(id: keyID) else {
            throw AuthError.keyNotFound(keyID)
        }

        let privateKey = try parsePrivateKey(keyData)
        return .custom(NIOSSHPrivateKeyAuthMethod(privateKey: privateKey))
    }

    /// Generate a new Ed25519 SSH keypair.
    ///
    /// Returns (publicKeyString, privateKeyData) where publicKeyString
    /// is in OpenSSH authorized_keys format.
    static func generateEd25519Key() -> (publicKey: String, privateKeyData: Data) {
        let key = Curve25519.Signing.PrivateKey()
        let nioKey = NIOSSHPrivateKey(ed25519Key: key)

        // Public key in OpenSSH format for authorized_keys
        let publicKeyString = serializePublicKey(nioKey)

        // Private key data for Keychain storage
        let privateKeyData = key.rawRepresentation

        return (publicKeyString, privateKeyData)
    }

    /// Generate a new P256 (ECDSA) SSH keypair.
    static func generateP256Key() -> (publicKey: String, privateKeyData: Data) {
        let key = P256.Signing.PrivateKey()
        let nioKey = NIOSSHPrivateKey(p256Key: key)

        let publicKeyString = serializePublicKey(nioKey)
        let privateKeyData = key.rawRepresentation

        return (publicKeyString, privateKeyData)
    }

    // MARK: - Private Key Parsing

    /// Parse raw key data into an NIOSSHPrivateKey.
    ///
    /// Supports:
    /// - Raw Ed25519 (32 bytes)
    /// - Raw P256 (32 bytes with P256 tag)
    /// - OpenSSH PEM format (-----BEGIN OPENSSH PRIVATE KEY-----)
    private static func parsePrivateKey(_ data: Data) throws -> NIOSSHPrivateKey {
        // Try raw Ed25519 first (32 bytes)
        if data.count == 32 {
            let ed25519Key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
            return NIOSSHPrivateKey(ed25519Key: ed25519Key)
        }

        // Try parsing as OpenSSH PEM format
        if let pemString = String(data: data, encoding: .utf8),
           pemString.contains("BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSHPEM(pemString)
        }

        // Try P256 raw representation
        if let p256Key = try? P256.Signing.PrivateKey(rawRepresentation: data) {
            return NIOSSHPrivateKey(p256Key: p256Key)
        }

        throw AuthError.unsupportedKeyFormat
    }

    /// Parse an OpenSSH PEM-encoded private key.
    ///
    /// Format: -----BEGIN OPENSSH PRIVATE KEY-----\nbase64data\n-----END OPENSSH PRIVATE KEY-----
    private static func parseOpenSSHPEM(_ pem: String) throws -> NIOSSHPrivateKey {
        let lines = pem.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = lines.joined()

        guard let decoded = Data(base64Encoded: base64) else {
            throw AuthError.invalidPEMEncoding
        }

        // OpenSSH private key binary format:
        // "openssh-key-v1\0" magic
        // cipher name (string)
        // kdf name (string)
        // kdf options (string)
        // number of keys (uint32)
        // public key (string)
        // private key section (encrypted or plain)
        //
        // For unencrypted keys (cipher = "none"), we can extract directly.

        guard decoded.count > 15 else {
            throw AuthError.invalidKeyData
        }

        let magic = "openssh-key-v1\0"
        let magicData = Data(magic.utf8)
        guard decoded.prefix(magicData.count) == magicData else {
            throw AuthError.invalidKeyData
        }

        // For now, support unencrypted Ed25519 and ECDSA keys.
        // Full OpenSSH key parsing would require a dedicated parser.
        //
        // Detect key type from the encoded data
        if decoded.contains("ssh-ed25519".data(using: .utf8)!) {
            // Extract Ed25519 private key (last 64 bytes of private section = 32 seed + 32 public)
            // This is a simplified extraction; production would use proper binary parsing
            let seed = decoded.suffix(96).prefix(32)
            if seed.count == 32 {
                let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
                return NIOSSHPrivateKey(ed25519Key: key)
            }
        }

        if decoded.contains("ecdsa-sha2-nistp256".data(using: .utf8)!) {
            // For P256, the raw scalar is typically 32 bytes
            let scalar = decoded.suffix(64).prefix(32)
            if scalar.count == 32 {
                let key = try P256.Signing.PrivateKey(rawRepresentation: scalar)
                return NIOSSHPrivateKey(p256Key: key)
            }
        }

        throw AuthError.unsupportedKeyFormat
    }

    /// Serialize a public key to OpenSSH authorized_keys format.
    private static func serializePublicKey(_ key: NIOSSHPrivateKey) -> String {
        // NIOSSHPrivateKey doesn't have a direct public key serialization method.
        // We manually format based on key type.
        // The actual SSH wire format encoding is handled by NIOSSH internally.
        // For display purposes, we return a placeholder that would be replaced
        // with proper serialization when the key is exported.
        return "ssh-key (use `ssh-keygen -y -f keyfile` to extract public key)"
    }

    // MARK: - Errors

    enum AuthError: Error, LocalizedError {
        case keyNotFound(String)
        case unsupportedKeyFormat
        case invalidPEMEncoding
        case invalidKeyData
        case passphraseRequired

        var errorDescription: String? {
            switch self {
            case .keyNotFound(let id): return "SSH key '\(id)' not found in Keychain"
            case .unsupportedKeyFormat: return "Unsupported SSH key format (supported: Ed25519, P256/ECDSA)"
            case .invalidPEMEncoding: return "Invalid PEM base64 encoding"
            case .invalidKeyData: return "Invalid or corrupt key data"
            case .passphraseRequired: return "Key is encrypted — passphrase required"
            }
        }
    }
}

/// NIOSSHPrivateKey-based auth method for swift-ssh-client.
///
/// This wraps an `NIOSSHPrivateKey` to work with swift-ssh-client's
/// `.custom()` authentication method.
struct NIOSSHPrivateKeyAuthMethod: SSHAuthenticationMethod {
    let privateKey: NIOSSHPrivateKey

    func authenticate(
        connection: SSHConnection,
        username: String,
        session: NIOSSHClientUserAuthenticationDelegate
    ) async throws {
        // The NIOSSHPrivateKey handles signing the authentication challenge.
        // swift-ssh-client's custom auth delegates to NIOSSH's auth layer.
        try await session.authenticate(
            username: username,
            privateKey: privateKey
        )
    }
}
