import Foundation

/// Data model for a saved SSH connection profile.
/// Uses SwiftData for persistence in the final build.
///
/// TODO: Add @Model macro when building with Xcode 26 SDK + SwiftData
struct ConnectionProfile: Identifiable, Hashable, Sendable, Codable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
    var authMethod: AuthMethod = .password
    var sshKeyID: String?
    var notes: AttributedString = AttributedString()
    var lastConnected: Date?
    var createdAt: Date = Date()

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ConnectionProfile, rhs: ConnectionProfile) -> Bool {
        lhs.id == rhs.id
    }
}

enum AuthMethod: String, Sendable, Codable, CaseIterable {
    case password
    case sshKey
}
