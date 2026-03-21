#if canImport(UIKit)
import Foundation
import GlassdeckCore
import Observation

/// Manages multiple concurrent SSH sessions and display routing.
///
/// Orchestrates the full lifecycle: connection → shell → PTY bridge → terminal.
/// Each session owns its own GhosttySurface, InteractiveShell, and SSHPTYBridge.
@Observable
@MainActor
final class SessionManager {
    struct SyntheticTerminalSeed {
        let title: String
        let transcript: String
        var terminalSize: TerminalSize?
        var terminalPixelSize: TerminalPixelSize?
        var scrollbackLines: Int?
        var interactionGeometry: RemoteTerminalGeometry?
        var interactionCapabilities: GhosttyVTInteractionCapabilities?
    }

    private(set) var sessions: [SSHSessionModel] = []
    private(set) var activeSessionID: UUID?
    private(set) var externalDisplaySessionID: UUID?
    private(set) var hasExternalDisplayConnected = false

    /// Whether the connection picker sheet is shown.
    var showConnectionPicker = false

    private let connectionManager = SSHConnectionManager()
    private let reconnectManager = SSHReconnectManager()

    var activeSession: SSHSessionModel? {
        sessions.first { $0.id == activeSessionID }
    }

    var externalDisplaySession: SSHSessionModel? {
        sessions.first { $0.id == externalDisplaySessionID }
    }

    var connectedSessions: [SSHSessionModel] {
        sessions.filter { $0.isConnected }
    }

    func shouldShowRemoteTrackpad(for session: SSHSessionModel) -> Bool {
        Self.remoteTrackpadEligibility(
            hasExternalDisplayConnected: hasExternalDisplayConnected,
            activeSessionID: activeSessionID,
            externalDisplaySessionID: externalDisplaySessionID,
            session: session
        )
    }

    static func remoteTrackpadEligibility(
        hasExternalDisplayConnected: Bool,
        activeSessionID: UUID?,
        externalDisplaySessionID: UUID?,
        session: SSHSessionModel
    ) -> Bool {
        hasExternalDisplayConnected
            && activeSessionID == session.id
            && externalDisplaySessionID == session.id
            && session.isLiveForRemoteControl
            && !session.remoteControlShowsLocalTerminal
    }

    /// Get the terminal surface for a session.
    func surface(for sessionID: UUID) -> GhosttySurface? {
        sessions.first { $0.id == sessionID }?.surface
    }

    func session(with id: UUID) -> SSHSessionModel? {
        sessions.first { $0.id == id }
    }

    func existingSession(for profile: ConnectionProfile) -> SSHSessionModel? {
        sessions
            .filter { $0.profile.id == profile.id }
            .sorted { lhs, rhs in
                if lhs.isConnected != rhs.isConnected {
                    return lhs.isConnected && !rhs.isConnected
                }
                return (lhs.connectedAt ?? .distantPast) > (rhs.connectedAt ?? .distantPast)
            }
            .first
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
    @discardableResult
    func connect(to profile: ConnectionProfile, password: String? = nil) async -> SSHSessionModel? {
        let session = SSHSessionModel(profile: profile)
        session.connectionPassword = password
        sessions.append(session)
        activeSessionID = session.id

        guard prepareSurface(for: session) else { return session }
        _ = await establishConnection(
            for: session,
            password: password,
            isReconnect: false
        )
        return session
    }

    /// Disconnect a specific session.
    func disconnect(sessionID: UUID? = nil) {
        let targetID = sessionID ?? activeSessionID
        guard let id = targetID,
              let session = sessions.first(where: { $0.id == id }) else { return }

        session.requestedManualDisconnect = true
        session.reconnectState = .idle
        session.connectionError = nil
        session.surface?.setFocused(false)
        session.status = .disconnected
        session.surface = nil
        session.remoteControlShowsLocalTerminal = false
        session.remoteControlKeyboardFocused = false
        session.remoteControlSoftwareKeyboardPresented = false
        session.remoteControlUnsupportedMessage = nil
        session.remotePointerOverlayState = .hidden
        Task {
            await reconnectManager.cancelReconnecting(sessionID: id)
            await self.teardownRemoteResources(for: session)
        }
    }

    /// Close and remove a session entirely.
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
    func setActiveSession(id: UUID, focusSurface: Bool = true) {
        if let previousActiveSessionID = activeSessionID,
           previousActiveSessionID != id,
           let previousSession = sessions.first(where: { $0.id == previousActiveSessionID }) {
            previousSession.remoteControlShowsLocalTerminal = false
            previousSession.remoteControlKeyboardFocused = false
            previousSession.remoteControlSoftwareKeyboardPresented = false
            previousSession.remoteControlUnsupportedMessage = nil
            previousSession.remotePointerOverlayState = .hidden
        }

        activeSessionID = id
        if let session = sessions.first(where: { $0.id == id }) {
            session.surface?.setFocused(focusSurface)
            session.remoteControlKeyboardFocused = shouldShowRemoteTrackpad(for: session)
        }
        for session in sessions where session.id != id {
            session.surface?.setFocused(false)
            session.remoteControlKeyboardFocused = false
        }
    }

    /// Open a new tab (shows connection picker).
    func openNewTab() {
        showConnectionPicker = true
    }

    @discardableResult
    func reconnect(sessionID: UUID) async -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        session.requestedManualDisconnect = false
        session.connectionError = nil
        session.reconnectState = .idle
        guard prepareSurface(for: session) else { return false }
        return await establishConnection(
            for: session,
            password: session.connectionPassword,
            isReconnect: true
        )
    }

    // MARK: - External Display Routing

    /// Route a session to the external display.
    func routeToExternalDisplay(sessionID: UUID) {
        // Unroute previous
        if let prevID = externalDisplaySessionID {
            if let previous = sessions.first(where: { $0.id == prevID }) {
                previous.isOnExternalDisplay = false
                previous.remotePointerOverlayState = .hidden
                previous.remoteControlShowsLocalTerminal = false
                previous.remoteControlUnsupportedMessage = nil
                previous.remoteControlKeyboardFocused = false
            }
        }

        externalDisplaySessionID = sessionID
        if let session = sessions.first(where: { $0.id == sessionID }) {
            session.isOnExternalDisplay = true
            session.remoteControlShowsLocalTerminal = false
            session.remotePointerOverlayState = .hidden
            session.remoteControlUnsupportedMessage = nil
            session.remoteControlKeyboardFocused = activeSessionID == sessionID && hasExternalDisplayConnected
        }

        // Post notification for ExternalDisplaySceneDelegate
        NotificationCenter.default.post(
            name: .externalDisplaySessionChanged,
            object: sessionID
        )
    }

    /// Remove external display routing.
    func clearExternalDisplay() {
        if let id = externalDisplaySessionID {
            if let session = sessions.first(where: { $0.id == id }) {
                session.isOnExternalDisplay = false
                session.remotePointerOverlayState = .hidden
                session.remoteControlShowsLocalTerminal = false
                session.remoteControlUnsupportedMessage = nil
                session.remoteControlKeyboardFocused = false
            }
        }
        externalDisplaySessionID = nil
        NotificationCenter.default.post(
            name: .externalDisplaySessionChanged,
            object: nil
        )
    }

    func setExternalDisplayConnected(_ isConnected: Bool) {
        hasExternalDisplayConnected = isConnected
        if !isConnected {
            for session in sessions {
                session.remoteControlKeyboardFocused = false
                session.remoteControlSoftwareKeyboardPresented = false
                session.remoteControlUnsupportedMessage = nil
                session.remotePointerOverlayState = .hidden
            }
        } else if let session = activeSession {
            session.remoteControlKeyboardFocused = shouldShowRemoteTrackpad(for: session)
        }
    }

    func showLocalTerminalForCurrentVisit(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.remoteControlShowsLocalTerminal = true
        session.remoteControlKeyboardFocused = false
        session.remoteControlSoftwareKeyboardPresented = false
        session.remotePointerOverlayState = .hidden
    }

    static func connectedSessionsHaveSurfaces(_ sessions: [SSHSessionModel]) -> Bool {
        sessions.allSatisfy { !$0.isConnected || $0.surface != nil }
    }

    @discardableResult
    func attachSyntheticSurfaceForPreview(
        to session: SSHSessionModel,
        seed: SyntheticTerminalSeed
    ) -> Bool {
        guard prepareSurface(for: session), let surface = session.surface else { return false }

        applySyntheticPreviewLayout(to: surface, seed: seed)
        surface.title = seed.title
        if !seed.transcript.isEmpty {
            surface.writeToTerminal(Data(seed.transcript.utf8))
        }

        applySurfaceState(surface.stateSnapshot, to: session)

        if let terminalSize = seed.terminalSize {
            session.terminalSize = terminalSize
        }
        if let terminalPixelSize = seed.terminalPixelSize {
            session.terminalPixelSize = terminalPixelSize
        }
        if let scrollbackLines = seed.scrollbackLines {
            session.scrollbackLines = scrollbackLines
        }
        if let interactionGeometry = seed.interactionGeometry {
            session.terminalInteractionGeometry = interactionGeometry
        }
        if let interactionCapabilities = seed.interactionCapabilities {
            session.terminalInteractionCapabilities = interactionCapabilities
        }

        return true
    }

    func replaceSessionsForPreview(
        _ previewSessions: [SSHSessionModel],
        activeSessionID: UUID?,
        externalDisplaySessionID: UUID?,
        hasExternalDisplayConnected: Bool
    ) {
        assert(
            Self.connectedSessionsHaveSurfaces(previewSessions),
            "Connected preview sessions must carry a bound GhosttySurface."
        )

        sessions = previewSessions
        self.activeSessionID = activeSessionID
        self.externalDisplaySessionID = externalDisplaySessionID
        self.hasExternalDisplayConnected = hasExternalDisplayConnected

        for session in sessions {
            session.isOnExternalDisplay = session.id == externalDisplaySessionID
            session.remoteControlKeyboardFocused = Self.remoteTrackpadEligibility(
                hasExternalDisplayConnected: hasExternalDisplayConnected,
                activeSessionID: activeSessionID,
                externalDisplaySessionID: externalDisplaySessionID,
                session: session
            )
        }
    }

    // MARK: - Private

    private func handleSessionDisconnect(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.bridge = nil
        session.surface?.setFocused(false)
        if session.requestedManualDisconnect {
            session.status = .disconnected
            session.connectionID = nil
            session.reconnectState = .idle
            return
        }

        if let connectionID = session.connectionID {
            Task {
                await connectionManager.disconnect(id: connectionID)
                await connectionManager.remove(id: connectionID)
            }
        }
        session.connectionID = nil
        session.status = .reconnecting

        Task { [weak self] in
            guard let self else { return }
            await self.reconnectManager.startReconnecting(
                sessionID: sessionID,
                reconnect: { [weak self] in
                    guard let self else { return false }
                    return await self.reconnectSession(sessionID: sessionID)
                },
                onStatusChange: { [weak self] status in
                    Task { @MainActor in
                        self?.applyReconnectStatus(status, to: sessionID)
                    }
                }
            )
        }
    }

    private func applySyntheticPreviewLayout(
        to surface: GhosttySurface,
        seed: SyntheticTerminalSeed
    ) {
        let scale = max(surface.traitCollection.displayScale, 1)

        let bounds: CGRect
        if let pixelSize = seed.terminalPixelSize {
            bounds = CGRect(
                x: 0,
                y: 0,
                width: max(CGFloat(pixelSize.width) / scale, 1),
                height: max(CGFloat(pixelSize.height) / scale, 1)
            )
        } else if let terminalSize = seed.terminalSize {
            bounds = CGRect(
                x: 0,
                y: 0,
                width: max(CGFloat(terminalSize.columns * 10), 1),
                height: max(CGFloat(terminalSize.rows * 20), 1)
            )
        } else {
            bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        }

        guard surface.bounds != bounds else { return }
        surface.frame = bounds
        surface.layoutIfNeeded()
    }

    private func prepareSurface(for session: SSHSessionModel) -> Bool {
        if let surface = session.surface {
            bind(surface: surface, to: session)
            applySurfaceState(surface.stateSnapshot, to: session)
            return true
        }

        do {
            let surface = try GhosttySurface()
            session.surface = surface
            bind(surface: surface, to: session)
            applySurfaceState(surface.stateSnapshot, to: session)
            return true
        } catch {
            session.status = .failed(error.localizedDescription)
            session.connectionError = error.localizedDescription
            return false
        }
    }

    private func bind(surface: GhosttySurface, to session: SSHSessionModel) {
        surface.onStateChange = { [weak session] state in
            session?.terminalTitle = state.title
            session?.terminalSize = state.terminalSize
            session?.terminalPixelSize = state.pixelSize
            session?.scrollbackLines = state.scrollbackLines
            session?.terminalIsHealthy = state.isHealthy
            session?.terminalRenderFailureReason = state.renderFailureReason
            session?.terminalVisibleTextSummary = state.visibleTextSummary
            session?.terminalInteractionGeometry = state.interactionGeometry
            session?.terminalInteractionCapabilities = state.interactionCapabilities
        }
    }

    private func applySurfaceState(_ state: GhosttySurfaceState, to session: SSHSessionModel) {
        session.terminalTitle = state.title
        session.terminalSize = state.terminalSize
        session.terminalPixelSize = state.pixelSize
        session.scrollbackLines = state.scrollbackLines
        session.terminalIsHealthy = state.isHealthy
        session.terminalRenderFailureReason = state.renderFailureReason
        session.terminalVisibleTextSummary = state.visibleTextSummary
        session.terminalInteractionGeometry = state.interactionGeometry
        session.terminalInteractionCapabilities = state.interactionCapabilities
    }

    private func establishConnection(
        for session: SSHSessionModel,
        password: String?,
        isReconnect: Bool
    ) async -> Bool {
        guard let surface = session.surface else {
            session.status = .failed("Terminal surface initialization failed")
            session.connectionError = "Terminal surface initialization failed"
            return false
        }

        session.requestedManualDisconnect = false
        session.connectionPassword = password
        session.connectionError = nil
        session.reconnectState = isReconnect ? session.reconnectState : .idle
        session.status = isReconnect ? .reconnecting : .connecting
        session.remoteControlUnsupportedMessage = nil
        session.remotePointerOverlayState = .hidden
        session.remoteControlKeyboardFocused = shouldShowRemoteTrackpad(for: session)

        await teardownRemoteResources(for: session)

        do {
            let connectionID = try await connectionManager.connect(
                to: session.profile,
                password: password
            )
            session.connectionID = connectionID
            session.status = .authenticating

            let shell = try await connectionManager.openShell(
                connectionID: connectionID,
                configuration: ShellLaunchConfiguration(
                    term: "xterm-256color",
                    size: surface.terminalSize,
                    pixelSize: surface.pixelSize
                )
            )

            let bridge = SSHPTYBridge(terminal: GhosttySurfaceTerminalIO(surface: surface))
            session.bridge = bridge

            surface.onResize = { [weak bridge, weak session] columns, rows, pixelSize in
                guard let bridge else { return }
                session?.terminalSize = TerminalSize(columns: columns, rows: rows)
                session?.terminalPixelSize = pixelSize
                Task {
                    await bridge.resize(columns: columns, rows: rows, pixelSize: pixelSize)
                }
            }

            await bridge.start(shell: shell)
            await bridge.setOnDisconnect { [weak self, sessionID = session.id] in
                Task { @MainActor in
                    self?.handleSessionDisconnect(sessionID: sessionID)
                }
            }

            session.connectedAt = Date()
            session.status = .connected
            session.reconnectState = isReconnect ? .reconnected : .idle
            session.remoteControlKeyboardFocused = shouldShowRemoteTrackpad(for: session)
            return true
        } catch {
            await teardownRemoteResources(for: session)
            session.connectionError = error.localizedDescription
            session.remoteControlKeyboardFocused = false
            if isReconnect {
                session.status = .reconnecting
            } else {
                session.status = .failed(error.localizedDescription)
            }
            return false
        }
    }

    private func reconnectSession(sessionID: UUID) async -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        guard prepareSurface(for: session) else { return false }
        return await establishConnection(
            for: session,
            password: session.connectionPassword,
            isReconnect: true
        )
    }

    private func applyReconnectStatus(
        _ status: SSHReconnectManager.ReconnectStatus,
        to sessionID: UUID
    ) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }

        switch status {
        case .attempting(let attempt, let maxAttempts):
            session.reconnectState = .attempting(attempt: attempt, maxAttempts: maxAttempts)
            session.status = .reconnecting
        case .reconnected:
            session.reconnectState = .reconnected
        case .gaveUp(let attempts):
            session.reconnectState = .gaveUp(attempts: attempts)
            session.status = .failed(status.label)
        }
    }

    private func teardownRemoteResources(for session: SSHSessionModel) async {
        let bridge = session.bridge
        let connectionID = session.connectionID
        session.bridge = nil
        session.connectionID = nil

        if let bridge {
            await bridge.stop()
        }

        if let connectionID {
            await connectionManager.disconnect(id: connectionID)
            await connectionManager.remove(id: connectionID)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let externalDisplaySessionChanged = Notification.Name("externalDisplaySessionChanged")
}
#endif
