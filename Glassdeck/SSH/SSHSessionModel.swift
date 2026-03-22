#if canImport(UIKit)
import Foundation
import GlassdeckCore
import Observation

/// Represents an active SSH session's state.
///
/// Each session tracks its SSH connection, shell, PTY bridge,
/// terminal dimensions, and connection lifecycle events.
@Observable
final class SSHSessionModel: Identifiable {
    let id: UUID
    let profile: ConnectionProfile

    // Connection lifecycle
    var status: SessionStatus = .disconnected
    var connectedAt: Date?
    var reconnectState: ReconnectState = .idle

    var connectionErrorMessage: String? {
        if case .failed(let reason) = status { return reason }
        return nil
    }

    // SSH internals (managed by SessionManager)
    var connectionID: UUID?
    var bridge: SSHPTYBridge?
    var surface: GhosttySurface?
    /// Terminal engine persists across surface recreations to preserve state.
    var engine: GhosttyVTTerminalEngine?
    var requestedManualDisconnect = false
    var connectionPassword: String?

    // Terminal state
    var terminalTitle: String?
    var terminalSize: TerminalSize = TerminalSize(columns: 80, rows: 24)
    var terminalPixelSize: TerminalPixelSize?
    var scrollbackLines: Int = 0
    var terminalIsHealthy = true
    var terminalRenderFailureReason: String?
    var terminalVisibleTextSummary = ""
    var terminalHasRenderedFrame = false
    var terminalAnimationProgress: GhosttyHomeAnimationProgress?
    var terminalInteractionGeometry: RemoteTerminalGeometry = .zero
    var terminalInteractionCapabilities = GhosttyVTInteractionCapabilities(
        supportsMousePlacement: false,
        supportsScrollReporting: false
    )

    // Display routing
    var isOnExternalDisplay: Bool = false
    var remoteControlMode: RemoteControlMode = .cursor
    var remotePointerOverlayState: RemotePointerOverlayState = .hidden
    var remoteControlUnsupportedMessage: String?
    var remoteControlShowsLocalTerminal = false
    var remoteControlKeyboardFocused = false
    var remoteControlSoftwareKeyboardPresented = false
    var localTerminalSoftwareKeyboardPresented = false
    var shouldRestoreConnectionOnForeground = false
    var wasRestoredFromPersistence = false

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

    var isLiveForRemoteControl: Bool {
        switch status {
        case .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    init(id: UUID = UUID(), profile: ConnectionProfile) {
        self.id = id
        self.profile = profile
    }

    enum ReconnectState: Sendable, Equatable {
        case idle
        case attempting(attempt: Int, maxAttempts: Int)
        case reconnected
        case gaveUp(attempts: Int)

        var label: String? {
            switch self {
            case .idle:
                nil
            case .attempting(let attempt, let maxAttempts):
                "Reconnecting (\(attempt)/\(maxAttempts))…"
            case .reconnected:
                "Reconnected"
            case .gaveUp(let attempts):
                "Reconnect failed after \(attempts) attempts"
            }
        }
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
#endif
