import Foundation

/// Data model for a saved SSH connection profile.
/// Uses SwiftData for persistence in the final build.
///
/// TODO: Add @Model macro when building with Xcode 26 SDK + SwiftData
public struct ConnectionProfile: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID = UUID()
    public var name: String
    public var host: String
    public var port: Int = 22
    public var username: String
    public var authMethod: AuthMethod = .password
    public var sshKeyID: String?
    public var notes: AttributedString = AttributedString()
    public var lastConnected: Date?
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        sshKeyID: String? = nil,
        notes: AttributedString = AttributedString(),
        lastConnected: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.sshKeyID = sshKeyID
        self.notes = notes
        self.lastConnected = lastConnected
        self.createdAt = createdAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ConnectionProfile, rhs: ConnectionProfile) -> Bool {
        lhs.id == rhs.id
    }
}

public enum AuthMethod: String, Sendable, Codable, CaseIterable {
    case password
    case sshKey
}
