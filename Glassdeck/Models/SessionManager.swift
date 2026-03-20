import Foundation
import SSHClient

/// Manages multiple concurrent SSH sessions and display routing.
///
/// Orchestrates the full lifecycle: connection → shell → PTY bridge → terminal.
/// Each session gets its own GhosttySurface, SSHShell, and SSHPTYBridge.
@Observable
final class SessionManager {
    private(set) var sessions: [SSHSessionModel] = []
    private(set) var activeSessionID: UUID?
    private(set) var externalDisplaySessionID: UUID?

    /// Whether the connection picker sheet is shown.
    var showConnectionPicker = false

    private let connectionManager = SSHConnectionManager()

    /// The GhosttyApp shared across all terminal surfaces.
    let ghosttyApp = GhosttyApp()

    /// Terminal surfaces keyed by session ID.
    private var surfaces: [UUID: GhosttySurface] = [:]

    var activeSession: SSHSessionModel? {
        sessions.first { $0.id == activeSessionID }
    }

    var externalDisplaySession: SSHSessionModel? {
        sessions.first { $0.id == externalDisplaySessionID }
    }

    var connectedSessions: [SSHSessionModel] {
        sessions.filter { $0.isConnected }
    }

    /// Get the terminal surface for a session.
    func surface(for sessionID: UUID) -> GhosttySurface? {
        surfaces[sessionID]
    }

    // MARK: - Connection Lifecycle

    /// Connect to a host, open a shell, and wire up the PTY bridge.
    ///
    /// Full flow:
    /// 1. Create session model & terminal surface
    /// 2. SSH connect & authenticate
    /// 3. Request PTY shell
    /// 4. Create PTY bridge (SSH shell ↔ terminal surface)
    /// 5. Start bidirectional I/O
    @MainActor
    func connect(to profile: ConnectionProfile, password: String? = nil) async {
        let session = SSHSessionModel(profile: profile)
        sessions.append(session)
        activeSessionID = session.id

        // 1. Create terminal surface on main thread (UIView)
        let surface = GhosttySurface(app: ghosttyApp)
        surfaces[session.id] = surface

        // 2. SSH connect
        session.status = .connecting
        do {
            let connectionID = try await connectionManager.connect(
                to: profile,
                password: password
            )
            session.connectionID = connectionID
            session.status = .authenticating

            // 3. Open PTY shell
            let shell = try await connectionManager.openShell(connectionID: connectionID)
            session.status = .connected
            session.connectedAt = Date()

            // 4. Create PTY bridge
            let bridge = SSHPTYBridge(surface: surface)
            session.bridge = bridge

            // 5. Wire resize callback
            surface.onResize = { [weak bridge] columns, rows in
                guard let bridge else { return }
                Task { await bridge.resize(columns: columns, rows: rows) }
            }

            // 6. Handle disconnect
            await bridge.start(shell: shell)
            Task {
                await bridge.onDisconnect = { [weak self, sessionID = session.id] in
                    Task { @MainActor in
                        self?.handleSessionDisconnect(sessionID: sessionID)
                    }
                }
            }

        } catch {
            session.status = .failed(error.localizedDescription)
            session.connectionError = error.localizedDescription
        }
    }

    /// Disconnect a specific session.
    @MainActor
    func disconnect(sessionID: UUID? = nil) {
        let targetID = sessionID ?? activeSessionID
        guard let id = targetID,
              let session = sessions.first(where: { $0.id == id }) else { return }

        // Stop PTY bridge
        if let bridge = session.bridge {
            Task { await bridge.stop() }
        }

        // Disconnect SSH
        if let connID = session.connectionID {
            Task { await connectionManager.disconnect(id: connID) }
        }

        session.status = .disconnected
        session.bridge = nil
        surfaces.removeValue(forKey: id)
    }

    /// Close and remove a session entirely.
    @MainActor
    func closeSession(id: UUID) {
        disconnect(sessionID: id)
        sessions.removeAll { $0.id == id }

        if activeSessionID == id {
            activeSessionID = sessions.last?.id
        }
        if externalDisplaySessionID == id {
            externalDisplaySessionID = nil
        }
    }

    // MARK: - Session Switching

    /// Switch the active on-device session.
    func setActiveSession(id: UUID) {
        activeSessionID = id
        // Focus the terminal surface
        if let surface = surfaces[id] {
            surface.setFocused(true)
        }
        // Unfocus previous
        for (sid, surf) in surfaces where sid != id {
            surf.setFocused(false)
        }
    }

    /// Open a new tab (shows connection picker).
    func openNewTab() {
        showConnectionPicker = true
    }

    // MARK: - External Display Routing

    /// Route a session to the external display.
    func routeToExternalDisplay(sessionID: UUID) {
        // Unroute previous
        if let prevID = externalDisplaySessionID {
            sessions.first { $0.id == prevID }?.isOnExternalDisplay = false
        }

        externalDisplaySessionID = sessionID
        sessions.first { $0.id == sessionID }?.isOnExternalDisplay = true

        // Post notification for ExternalDisplaySceneDelegate
        NotificationCenter.default.post(
            name: .externalDisplaySessionChanged,
            object: sessionID
        )
    }

    /// Remove external display routing.
    func clearExternalDisplay() {
        if let id = externalDisplaySessionID {
            sessions.first { $0.id == id }?.isOnExternalDisplay = false
        }
        externalDisplaySessionID = nil
        NotificationCenter.default.post(
            name: .externalDisplaySessionChanged,
            object: nil
        )
    }

    // MARK: - Private

    @MainActor
    private func handleSessionDisconnect(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.status = .disconnected
        session.bridge = nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let externalDisplaySessionChanged = Notification.Name("externalDisplaySessionChanged")
}
