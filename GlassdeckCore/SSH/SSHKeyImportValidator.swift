import Foundation

public struct SSHKeyImportPreview: Sendable, Equatable {
    public let name: String
    public let publicKey: String
    public let privateKeyData: Data

    public init(name: String, publicKey: String, privateKeyData: Data) {
        self.name = name
        self.publicKey = publicKey
        self.privateKeyData = privateKeyData
    }
}

public enum SSHKeyImportValidator {
    public static func preview(
        name: String? = nil,
        privateKeyData: Data
    ) throws -> SSHKeyImportPreview {
        let normalizedData = normalize(privateKeyData)
        let publicKey = try SSHAuthenticator.publicKeyString(fromPrivateKeyData: normalizedData)
        return SSHKeyImportPreview(
            name: sanitizedName(name) ?? defaultName(for: publicKey),
            publicKey: publicKey,
            privateKeyData: normalizedData
        )
    }

    public static func preview(
        name: String? = nil,
        privateKeyText: String
    ) throws -> SSHKeyImportPreview {
        try preview(
            name: name,
            privateKeyData: Data(privateKeyText.utf8)
        )
    }

    public static func `import`(
        name: String? = nil,
        privateKeyData: Data,
        keyManager: SSHKeyManager = .shared
    ) throws -> (id: String, preview: SSHKeyImportPreview) {
        let preview = try preview(name: name, privateKeyData: privateKeyData)
        let keyID = try keyManager.importKey(
            name: preview.name,
            pemData: preview.privateKeyData
        )
        return (keyID, preview)
    }

    private static func sanitize(_ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else {
            return data
        }

        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(normalized.utf8)
    }

    private static func normalize(_ data: Data) -> Data {
        sanitize(data)
    }

    private static func sanitizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func defaultName(for publicKey: String) -> String {
        let parts = publicKey.split(separator: " ", omittingEmptySubsequences: true)
        let algorithm = parts.first.map(String.init) ?? "ssh-key"
        let blobPrefix = parts.dropFirst().first.map { String($0.prefix(8)) } ?? "imported"
        return "\(algorithm)-\(blobPrefix)"
    }
}
