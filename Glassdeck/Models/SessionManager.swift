import Foundation

/// Manages multiple concurrent SSH sessions and display routing.
@Observable
final class SessionManager {
    private(set) var sessions: [SSHSessionModel] = []
    private(set) var activeSessionID: UUID?
    private(set) var externalDisplaySessionID: UUID?

    private let connectionManager = SSHConnectionManager()

    var activeSession: SSHSessionModel? {
        sessions.first { $0.id == activeSessionID }
    }

    var externalDisplaySession: SSHSessionModel? {
        sessions.first { $0.id == externalDisplaySessionID }
    }

    /// Connect to a host and create a new session.
    func connect(to profile: ConnectionProfile) async {
        let session = SSHSessionModel(profile: profile)
        sessions.append(session)
        activeSessionID = session.id

        do {
            _ = try await connectionManager.connect(to: profile)
            session.isConnected = true
        } catch {
            session.connectionError = error.localizedDescription
        }
    }

    /// Disconnect the active session.
    func disconnect() {
        guard let id = activeSessionID else { return }
        Task {
            await connectionManager.disconnect(id: id)
        }
        if let session = activeSession {
            session.isConnected = false
        }
    }

    /// Switch the active session.
    func setActiveSession(id: UUID) {
        activeSessionID = id
    }

    /// Open a new tab (prompts for connection).
    func openNewTab() {
        // Handled by the UI layer — triggers connection selection flow
    }

    /// Route a session to the external display.
    func routeToExternalDisplay(sessionID: UUID) {
        externalDisplaySessionID = sessionID
    }

    /// Remove external display routing.
    func clearExternalDisplay() {
        externalDisplaySessionID = nil
    }
}
