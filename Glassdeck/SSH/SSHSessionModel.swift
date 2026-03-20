import Foundation
import SSHClient

/// Represents an active SSH session's state.
///
/// Each session tracks its SSH connection, shell, PTY bridge,
/// terminal dimensions, and connection lifecycle events.
@Observable
final class SSHSessionModel: Identifiable {
    let id: UUID
    let profile: ConnectionProfile

    // Connection lifecycle
    nonisolated(unsafe) var status: SessionStatus = .disconnected
    nonisolated(unsafe) var connectionError: String?
    nonisolated(unsafe) var connectedAt: Date?

    // SSH internals (managed by SessionManager)
    nonisolated(unsafe) var connectionID: UUID?
    nonisolated(unsafe) var bridge: SSHPTYBridge?

    // Terminal state
    nonisolated(unsafe) var terminalTitle: String?
    nonisolated(unsafe) var terminalSize: TerminalSize = TerminalSize(columns: 80, rows: 24)
    nonisolated(unsafe) var scrollbackLines: Int = 0

    // Display routing
    nonisolated(unsafe) var isOnExternalDisplay: Bool = false

    var displayName: String {
        terminalTitle ?? "\(profile.username)@\(profile.host)"
    }

    var shortName: String {
        profile.name.isEmpty ? profile.host : profile.name
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    init(id: UUID = UUID(), profile: ConnectionProfile) {
        self.id = id
        self.profile = profile
    }

    enum SessionStatus: Sendable, Equatable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case reconnecting
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .authenticating: return "Authenticating…"
            case .connected: return "Connected"
            case .reconnecting: return "Reconnecting…"
            case .failed(let msg): return "Failed: \(msg)"
            }
        }

        var systemImage: String {
            switch self {
            case .disconnected: return "bolt.slash"
            case .connecting, .authenticating, .reconnecting: return "bolt.horizontal"
            case .connected: return "bolt.fill"
            case .failed: return "exclamationmark.triangle"
            }
        }
    }
}
