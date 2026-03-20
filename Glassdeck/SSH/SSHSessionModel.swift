import Foundation

/// Represents an active SSH session's state.
@Observable
final class SSHSessionModel: Identifiable, Sendable {
    let id: UUID
    let profile: ConnectionProfile
    nonisolated(unsafe) var isConnected: Bool = false
    nonisolated(unsafe) var connectionError: String?

    var displayName: String {
        "\(profile.username)@\(profile.host)"
    }

    init(id: UUID = UUID(), profile: ConnectionProfile) {
        self.id = id
        self.profile = profile
    }
}
