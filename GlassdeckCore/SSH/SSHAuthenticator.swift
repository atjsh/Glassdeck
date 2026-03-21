import Crypto
import Foundation
import NIOCore
import NIOSSH
import SSHClient

/// Handles SSH authentication: password and public key.
///
/// Supports:
/// - Password authentication
/// - SSH key authentication (Ed25519, P256/ECDSA from storage)
/// - Key generation (Ed25519, P256)
/// - OpenSSH private key parsing (unencrypted PEM format)
public struct SSHAuthenticator: Sendable {
    public enum AuthResult: Sendable {
        case success
        case failure(String)
    }

    public static func passwordMethod(_ password: String) -> SSHAuthentication.Method {
        .password(.init(password))
    }

    public static func keyMethod(
        username: String,
        keyID: String,
        passphrase: String? = nil
    ) throws -> SSHAuthentication.Method {
        guard let keyData = SSHKeyManager.shared.loadPrivateKey(id: keyID) else {
            throw AuthError.keyNotFound(keyID)
        }

        guard passphrase == nil else {
            throw AuthError.passphraseRequired
        }

        let privateKey = try parsePrivateKey(keyData)
        return .custom(NIOSSHPrivateKeyAuthDelegate(username: username, privateKey: privateKey))
    }

    public static func generateEd25519Key() -> (publicKey: String, privateKeyData: Data) {
        let key = Curve25519.Signing.PrivateKey()
        let nioKey = NIOSSHPrivateKey(ed25519Key: key)
        return (
            publicKey: serializePublicKey(nioKey),
            privateKeyData: key.rawRepresentation
        )
    }

    public static func generateP256Key() -> (publicKey: String, privateKeyData: Data) {
        let key = P256.Signing.PrivateKey()
        let nioKey = NIOSSHPrivateKey(p256Key: key)
        return (
            publicKey: serializePublicKey(nioKey),
            privateKeyData: key.rawRepresentation
        )
    }

    public static func publicKeyString(fromPrivateKeyData data: Data) throws -> String {
        serializePublicKey(try parsePrivateKey(data))
    }

    private static func parsePrivateKey(_ data: Data) throws -> NIOSSHPrivateKey {
        if data.count == 32 {
            if let ed25519Key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
                return NIOSSHPrivateKey(ed25519Key: ed25519Key)
            }

            if let p256Key = try? P256.Signing.PrivateKey(rawRepresentation: data) {
                return NIOSSHPrivateKey(p256Key: p256Key)
            }
        }

        if let pemString = String(data: data, encoding: .utf8),
           pemString.contains("BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSHPEM(pemString)
        }

        throw AuthError.unsupportedKeyFormat
    }

    private static func parseOpenSSHPEM(_ pem: String) throws -> NIOSSHPrivateKey {
        let lines = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        guard let decoded = Data(base64Encoded: lines.joined()) else {
            throw AuthError.invalidPEMEncoding
        }

        var parser = OpenSSHPrivateKeyParser(data: decoded)
        return try parser.parse()
    }

    private static func serializePublicKey(_ key: NIOSSHPrivateKey) -> String {
        String(openSSHPublicKey: key.publicKey)
    }

    public enum AuthError: Error, LocalizedError {
        case keyNotFound(String)
        case unsupportedKeyFormat
        case invalidPEMEncoding
        case invalidKeyData
        case unsupportedKeyType(String)
        case unsupportedCurve(String)
        case encryptedKeyUnsupported
        case passphraseRequired

        public var errorDescription: String? {
            switch self {
            case .keyNotFound(let id):
                return "SSH key '\(id)' not found in storage"
            case .unsupportedKeyFormat:
                return "Unsupported SSH key format (supported: raw Ed25519/P-256 or unencrypted OpenSSH PEM)"
            case .invalidPEMEncoding:
                return "Invalid PEM base64 encoding"
            case .invalidKeyData:
                return "Invalid or corrupt key data"
            case .unsupportedKeyType(let type):
                return "Unsupported SSH key type: \(type)"
            case .unsupportedCurve(let curve):
                return "Unsupported SSH curve: \(curve)"
            case .encryptedKeyUnsupported:
                return "Encrypted OpenSSH keys are not supported in this build"
            case .passphraseRequired:
                return "Encrypted keys require passphrase support that is not implemented yet"
            }
        }
    }
}

final class NIOSSHPrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private var privateKey: NIOSSHPrivateKey?

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey), let privateKey else {
            nextChallengePromise.succeed(nil)
            return
        }

        self.privateKey = nil
        nextChallengePromise.succeed(
            .init(
                username: username,
                serviceName: "ssh-connection",
                offer: .privateKey(.init(privateKey: privateKey))
            )
        )
    }
}

private struct OpenSSHPrivateKeyParser {
    private static let magic = Data("openssh-key-v1\u{0}".utf8)

    private var cursor: DataCursor

    init(data: Data) {
        self.cursor = DataCursor(data: data)
    }

    mutating func parse() throws -> NIOSSHPrivateKey {
        guard cursor.read(count: Self.magic.count) == Self.magic else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }

        let cipher = try cursor.readString()
        let kdf = try cursor.readString()
        _ = try cursor.readDataString()
        let keyCount = try cursor.readUInt32()

        guard cipher == "none", kdf == "none" else {
            throw SSHAuthenticator.AuthError.encryptedKeyUnsupported
        }

        guard keyCount == 1 else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }

        _ = try cursor.readDataString()
        let privateSection = try cursor.readDataString()

        var privateCursor = DataCursor(data: privateSection)
        let checkOne = try privateCursor.readUInt32()
        let checkTwo = try privateCursor.readUInt32()
        guard checkOne == checkTwo else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }

        let keyType = try privateCursor.readString()
        let privateKey: NIOSSHPrivateKey
        switch keyType {
        case "ssh-ed25519":
            _ = try privateCursor.readDataString()
            let privateBytes = try privateCursor.readDataString()
            _ = try privateCursor.readString()
            guard privateBytes.count >= 32 else {
                throw SSHAuthenticator.AuthError.invalidKeyData
            }
            let seed = privateBytes.prefix(32)
            privateKey = try NIOSSHPrivateKey(
                ed25519Key: Curve25519.Signing.PrivateKey(rawRepresentation: Data(seed))
            )
        case "ecdsa-sha2-nistp256":
            let curve = try privateCursor.readString()
            guard curve == "nistp256" else {
                throw SSHAuthenticator.AuthError.unsupportedCurve(curve)
            }
            _ = try privateCursor.readDataString()
            let scalar = try normalizeScalar(try privateCursor.readDataString(), expectedByteCount: 32)
            _ = try privateCursor.readString()
            privateKey = try NIOSSHPrivateKey(
                p256Key: P256.Signing.PrivateKey(rawRepresentation: scalar)
            )
        default:
            throw SSHAuthenticator.AuthError.unsupportedKeyType(keyType)
        }

        try validatePadding(in: privateCursor.remainingData())
        return privateKey
    }

    private func normalizeScalar(_ bytes: Data, expectedByteCount: Int) throws -> Data {
        let stripped = bytes.drop(while: { $0 == 0 })
        if stripped.count > expectedByteCount {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }
        if stripped.count == expectedByteCount {
            return Data(stripped)
        }
        return Data(repeating: 0, count: expectedByteCount - stripped.count) + stripped
    }

    private func validatePadding(in bytes: Data) throws {
        for (index, byte) in bytes.enumerated() {
            let expected = UInt8((index + 1) & 0xff)
            guard byte == expected else {
                throw SSHAuthenticator.AuthError.invalidKeyData
            }
        }
    }
}

private struct DataCursor {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func read(count: Int) -> Data? {
        guard offset + count <= data.count else { return nil }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readUInt32() throws -> UInt32 {
        guard let bytes = read(count: 4) else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }

        return bytes.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }

    mutating func readDataString() throws -> Data {
        let length = Int(try readUInt32())
        guard let value = read(count: length) else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }
        return value
    }

    mutating func readString() throws -> String {
        let value = try readDataString()
        guard let string = String(data: value, encoding: .utf8) else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }
        return string
    }

    func remainingData() throws -> Data {
        guard offset <= data.count else {
            throw SSHAuthenticator.AuthError.invalidKeyData
        }
        return data.suffix(from: offset)
    }
}
