#if canImport(UIKit)
import Foundation
import GlassdeckCore
import Observation

@MainActor
protocol SessionManagerLifecycleDelegate: AnyObject {
    func sessionManagerDidChangeSessions(_ sessionManager: SessionManager)
}

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
        var terminalConfiguration: TerminalConfiguration?
        var terminalMetricsPreset: GhosttySurfaceMetricsPreset?
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
    private(set) var presentationRevision = 0

    /// Whether the connection picker sheet is shown.
    var showConnectionPicker = false

    private let connectionManager = SSHConnectionManager()
    private var reconnectManager: SSHReconnectManager
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let persistenceStore: SessionPersistenceStore
    @ObservationIgnored private let credentialStore: SessionCredentialStore
    @ObservationIgnored private var restoredPersistedSessions = false
    weak var lifecycleDelegate: SessionManagerLifecycleDelegate?

    init(
        appSettings: AppSettings = AppSettings(),
        persistenceStore: SessionPersistenceStore = SessionPersistenceStore(),
        credentialStore: SessionCredentialStore = SessionCredentialStore()
    ) {
        self.appSettings = appSettings
        self.persistenceStore = persistenceStore
        self.credentialStore = credentialStore
        self.reconnectManager = SSHReconnectManager(
            config: Self.reconnectConfig(from: appSettings)
        )
        restorePersistedSessionsIfNeeded()
    }

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

    var hasLiveSessionsNeedingRuntimeSupport: Bool {
        sessions.contains { session in
            switch session.status {
            case .connected, .connecting, .authenticating, .reconnecting:
                return true
            case .disconnected, .failed:
                return false
            }
        }
    }

    func isTerminalPresentationReady(for session: SSHSessionModel) -> Bool {
        session.surface != nil && session.terminalHasRenderedFrame
    }

    func isSessionDetailPresentable(for session: SSHSessionModel) -> Bool {
        shouldShowRemoteTrackpad(for: session) || isTerminalPresentationReady(for: session)
    }

    func terminalDisplayTarget(for session: SSHSessionModel) -> TerminalDisplayTarget {
        guard hasExternalDisplayConnected, externalDisplaySessionID == session.id else {
            return .iphone
        }
        return .externalMonitor
    }

    func refreshTerminalConfiguration(for target: TerminalDisplayTarget) async {
        let targetSessionIDs = sessions.compactMap { session -> UUID? in
            guard session.surface != nil else { return nil }
            return terminalDisplayTarget(for: session) == target ? session.id : nil
        }

        for sessionID in targetSessionIDs {
            await refreshTerminalConfiguration(for: sessionID)
        }
    }

    func restorePersistedSessionsIfNeeded() {
        guard !restoredPersistedSessions else { return }
        restoredPersistedSessions = true
        guard let snapshot = persistenceStore.loadSnapshot() else { return }

        sessions = snapshot.sessions.map(Self.session(from:))
        activeSessionID = snapshot.activeSessionID
        externalDisplaySessionID = snapshot.externalDisplaySessionID

        for session in sessions {
            session.isOnExternalDisplay = session.id == externalDisplaySessionID
            if session.profile.authMethod == .password {
                session.connectionPassword = credentialStore.password(for: session.profile.id)
            }
        }

        persistSessions()
        notifySessionChanges()
    }

    func resumeRestorableSessionsIfNeeded() {
        for session in sessions where session.shouldRestoreConnectionOnForeground {
            switch session.status {
            case .connected, .connecting, .authenticating:
                continue
            case .reconnecting:
                Task {
                    _ = await reconnect(sessionID: session.id)
                }
            case .disconnected, .failed:
                Task {
                    _ = await reconnect(sessionID: session.id)
                }
            }
        }
    }

    func handleAppDidEnterBackground() {
        for session in sessions {
            switch session.status {
            case .connected, .connecting, .authenticating, .reconnecting:
                session.shouldRestoreConnectionOnForeground = true
            case .disconnected, .failed:
                break
            }
        }
        persistSessions()
    }

    func handleAppDidBecomeActive() {
        refreshReconnectManager()
        resumeRestorableSessionsIfNeeded()
    }

    func refreshReconnectConfiguration() {
        refreshReconnectManager()
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
        persistSessions()
        notifySessionChanges()

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
        session.surface?.setFocused(false)
        session.status = .disconnected
        session.surface = nil
        session.shouldRestoreConnectionOnForeground = false
        session.terminalHasRenderedFrame = false
        session.remoteControlKeyboardFocused = false
        session.remoteControlSoftwareKeyboardPresented = false
        session.localTerminalSoftwareKeyboardPresented = false
        session.remoteControlUnsupportedMessage = nil
        session.remotePointerOverlayState = .hidden
        persistSessions()
        notifySessionChanges()
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
        persistSessions()
        notifySessionChanges()
    }

    // MARK: - Session Switching

    /// Switch the active on-device session.
    func setActiveSession(id: UUID, focusSurface: Bool = true) {
        if let previousActiveSessionID = activeSessionID,
           previousActiveSessionID != id,
           let previousSession = sessions.first(where: { $0.id == previousActiveSessionID }) {
            previousSession.remoteControlKeyboardFocused = false
            previousSession.remoteControlSoftwareKeyboardPresented = false
            previousSession.remoteControlUnsupportedMessage = nil
            previousSession.remotePointerOverlayState = .hidden
        }

        activeSessionID = id
        if let session = sessions.first(where: { $0.id == id }) {
            session.surface?.setFocused(focusSurface && shouldFocusSurface(for: session))
            session.remoteControlKeyboardFocused = shouldShowRemoteTrackpad(for: session)
        }
        for session in sessions where session.id != id {
            session.surface?.setFocused(shouldFocusSurface(for: session))
            session.remoteControlKeyboardFocused = false
        }
        persistSessions()
        notifySessionChanges()
    }

    /// Open a new tab (shows connection picker).
    func openNewTab() {
        showConnectionPicker = true
    }

    @discardableResult
    func reconnect(sessionID: UUID) async -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        session.requestedManualDisconnect = false
        session.reconnectState = .idle
        session.shouldRestoreConnectionOnForeground = true
        if session.connectionPassword == nil, session.profile.authMethod == .password {
            session.connectionPassword = credentialStore.password(for: session.profile.id)
        }
        persistSessions()
        notifySessionChanges()
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
        let previousExternalSessionID = externalDisplaySessionID

        // Unroute previous
        if let prevID = externalDisplaySessionID {
            if let previous = sessions.first(where: { $0.id == prevID }) {
                previous.isOnExternalDisplay = false
                previous.remotePointerOverlayState = .hidden
                previous.remoteControlUnsupportedMessage = nil
                previous.remoteControlKeyboardFocused = false
                previous.localTerminalSoftwareKeyboardPresented = false
            }
        }

        externalDisplaySessionID = sessionID
        if let session = sessions.first(where: { $0.id == sessionID }) {
            session.isOnExternalDisplay = true
            session.remotePointerOverlayState = .hidden
            session.remoteControlUnsupportedMessage = nil
            session.remoteControlKeyboardFocused = activeSessionID == sessionID && hasExternalDisplayConnected
            session.localTerminalSoftwareKeyboardPresented = false
        }

        // Post notification for ExternalDisplaySceneDelegate
        NotificationCenter.default.post(
            name: .externalDisplaySessionChanged,
            object: sessionID
        )
        persistSessions()
        notifySessionChanges()

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let previousExternalSessionID, previousExternalSessionID != sessionID {
                await self.refreshTerminalConfiguration(for: previousExternalSessionID)
            }
            await self.refreshTerminalConfiguration(for: sessionID)
        }
    }

    /// Remove external display routing.
    func clearExternalDisplay() {
        let previousExternalSessionID = externalDisplaySessionID
        if let id = externalDisplaySessionID {
            if let session = sessions.first(where: { $0.id == id }) {
                session.isOnExternalDisplay = false
                session.remotePointerOverlayState = .hidden
                session.remoteControlUnsupportedMessage = nil
                session.remoteControlKeyboardFocused = false
                session.localTerminalSoftwareKeyboardPresented = false
            }
        }
        externalDisplaySessionID = nil
        NotificationCenter.default.post(
            name: .externalDisplaySessionChanged,
            object: nil
        )
        persistSessions()
        notifySessionChanges()

        if let previousExternalSessionID {
            Task { @MainActor [weak self] in
                await self?.refreshTerminalConfiguration(for: previousExternalSessionID)
            }
        }
    }

    func setExternalDisplayConnected(_ isConnected: Bool) {
        let previousExternalDisplayConnected = hasExternalDisplayConnected
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
            if externalDisplaySessionID == session.id {
                session.localTerminalSoftwareKeyboardPresented = false
            }
        }
        persistSessions()
        notifySessionChanges()

        guard previousExternalDisplayConnected != isConnected,
              let externalDisplaySessionID
        else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.refreshTerminalConfiguration(for: externalDisplaySessionID)
        }
    }

    static func connectedSessionsHaveSurfaces(_ sessions: [SSHSessionModel]) -> Bool {
        sessions.allSatisfy { !$0.isConnected || $0.surface != nil }
    }

    @discardableResult
    func attachSyntheticSurfaceForPreview(
        to session: SSHSessionModel,
        seed: SyntheticTerminalSeed
    ) -> Bool {
        guard
            prepareSurface(
                for: session,
                configuration: seed.terminalConfiguration,
                metricsPreset: seed.terminalMetricsPreset
            ),
            let surface = session.surface
        else {
            return false
        }

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

        persistSessions()
        notifySessionChanges()
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
            _ = prepareSurface(for: session)
        }
        persistSessions()
        notifySessionChanges()
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
            session.shouldRestoreConnectionOnForeground = false
            persistSessions()
            notifySessionChanges()
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
        session.shouldRestoreConnectionOnForeground = appSettings.autoReconnect
        persistSessions()
        notifySessionChanges()

        guard appSettings.autoReconnect else {
            session.status = .disconnected
            persistSessions()
            notifySessionChanges()
            return
        }

        refreshReconnectManager()

        Task { [weak self] in
            guard let self else { return }
            await self.reconnectManager.startReconnecting(
                sessionID: sessionID,
                reconnect: { [weak self] in
                    guard let self else { return .failure(.permanent("Session manager deallocated")) }
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
            bounds = GhosttySurface.previewBounds(
                for: terminalSize,
                configuration: seed.terminalConfiguration ?? TerminalConfiguration(),
                metricsPreset: seed.terminalMetricsPreset
            )
        } else {
            bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        }

        guard surface.bounds != bounds else { return }
        surface.frame = bounds
        surface.layoutIfNeeded()
    }

    private func prepareSurface(
        for session: SSHSessionModel,
        configuration: TerminalConfiguration? = nil,
        metricsPreset: GhosttySurfaceMetricsPreset? = nil
    ) -> Bool {
        let resolvedConfiguration = configuration ?? appSettings.terminalConfig(
            for: terminalDisplayTarget(for: session)
        )

        if let surface = session.surface {
            guard surface.terminalConfiguration == resolvedConfiguration else {
                guard session.bridge == nil else {
                    bind(surface: surface, to: session)
                    applySessionPresentationState(to: surface, session: session)
                    applySurfaceState(surface.stateSnapshot, to: session)
                    return true
                }

                do {
                    let replacementSurface = try GhosttySurface(
                        configuration: resolvedConfiguration,
                        metricsPreset: metricsPreset
                    )
                    replacementSurface.frame = surface.frame
                    replacementSurface.bounds = surface.bounds
                    replacementSurface.title = session.terminalTitle
                    surface.onResize = nil
                    surface.onStateChange = nil
                    surface.onSoftwareKeyboardPresentationChange = nil
                    session.surface = replacementSurface
                    bind(surface: replacementSurface, to: session)
                    applySessionPresentationState(to: replacementSurface, session: session)
                    applySurfaceState(replacementSurface.stateSnapshot, to: session)
                    return true
                } catch {
                    session.status = .failed(error.localizedDescription)
                    persistSessions()
                    notifySessionChanges()
                    return false
                }
            }

            bind(surface: surface, to: session)
            applySessionPresentationState(to: surface, session: session)
            applySurfaceState(surface.stateSnapshot, to: session)
            return true
        }

        do {
            let surface = try GhosttySurface(
                configuration: resolvedConfiguration,
                metricsPreset: metricsPreset
            )
            session.surface = surface
            bind(surface: surface, to: session)
            applySessionPresentationState(to: surface, session: session)
            applySurfaceState(surface.stateSnapshot, to: session)
            persistSessions()
            notifySessionChanges()
            return true
        } catch {
            session.status = .failed(error.localizedDescription)
            persistSessions()
            notifySessionChanges()
            return false
        }
    }

    private func bind(surface: GhosttySurface, to session: SSHSessionModel) {
        surface.onSoftwareKeyboardPresentationChange = { [weak session] presented in
            session?.localTerminalSoftwareKeyboardPresented = presented
        }
        surface.onStateChange = { [weak self, weak session] state in
            guard let self, let session else { return }
            self.applySurfaceState(state, to: session)
        }
    }

    private func bindResize(
        for surface: GhosttySurface,
        bridge: SSHPTYBridge?,
        session: SSHSessionModel
    ) {
        surface.onResize = { [weak bridge, weak session] columns, rows, pixelSize in
            guard let bridge else { return }
            session?.terminalSize = TerminalSize(columns: columns, rows: rows)
            session?.terminalPixelSize = pixelSize
            Task {
                await bridge.resize(columns: columns, rows: rows, pixelSize: pixelSize)
            }
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
        session.terminalHasRenderedFrame = state.hasRenderedFrame
        session.terminalAnimationProgress = state.animationProgress
        session.terminalInteractionGeometry = state.interactionGeometry
        session.terminalInteractionCapabilities = state.interactionCapabilities
        session.localTerminalSoftwareKeyboardPresented = state.softwareKeyboardPresented
        presentationRevision &+= 1
    }

    private func applySessionPresentationState(to surface: GhosttySurface, session: SSHSessionModel) {
        let localKeyboardPresented: Bool
        switch terminalDisplayTarget(for: session) {
        case .iphone:
            localKeyboardPresented = session.localTerminalSoftwareKeyboardPresented
        case .externalMonitor:
            localKeyboardPresented = false
            session.localTerminalSoftwareKeyboardPresented = false
        }

        surface.setSoftwareKeyboardPresented(localKeyboardPresented)
        surface.setFocused(shouldFocusSurface(for: session))
    }

    private func shouldFocusSurface(for session: SSHSessionModel) -> Bool {
        guard session.isLiveForRemoteControl else { return false }
        switch terminalDisplayTarget(for: session) {
        case .iphone:
            return activeSessionID == session.id
        case .externalMonitor:
            return true
        }
    }

    private func refreshTerminalConfiguration(for sessionID: UUID) async {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        guard let existingSurface = session.surface else { return }
        let configuration = appSettings.terminalConfig(for: terminalDisplayTarget(for: session))

        guard existingSurface.terminalConfiguration != configuration else {
            applySessionPresentationState(to: existingSurface, session: session)
            return
        }

        await recreateSurface(for: session, configuration: configuration)
    }

    private func recreateSurface(
        for session: SSHSessionModel,
        configuration: TerminalConfiguration
    ) async {
        let previousSurface = session.surface

        do {
            let surface: GhosttySurface
            if let existingEngine = session.engine {
                // Reuse the existing engine to preserve terminal state (scrollback, modes, colors)
                surface = try GhosttySurface(configuration: configuration, engine: existingEngine)
            } else {
                surface = try GhosttySurface(configuration: configuration)
                session.engine = surface.engine
            }

            if let previousSurface {
                previousSurface.onResize = nil
                previousSurface.onStateChange = nil
                previousSurface.onSoftwareKeyboardPresentationChange = nil
                surface.frame = previousSurface.frame
                surface.bounds = previousSurface.bounds
                surface.title = session.terminalTitle
            }

            session.surface = surface
            bind(surface: surface, to: session)
            applySessionPresentationState(to: surface, session: session)
            applySurfaceState(surface.stateSnapshot, to: session)

            if let bridge = session.bridge {
                bindResize(for: surface, bridge: bridge, session: session)
                await bridge.replaceTerminal(GhosttySurfaceTerminalIO(surface: surface))
                await bridge.resize(
                    columns: session.terminalSize.columns,
                    rows: session.terminalSize.rows,
                    pixelSize: session.terminalPixelSize
                )
            }

            persistSessions()
            notifySessionChanges()
        } catch {
            session.terminalRenderFailureReason = error.localizedDescription
            persistSessions()
            notifySessionChanges()
        }
    }

    private func establishConnection(
        for session: SSHSessionModel,
        password: String?,
        isReconnect: Bool
    ) async -> Bool {
        guard let surface = session.surface else {
            session.status = .failed("Terminal surface initialization failed")
            return false
        }

        session.requestedManualDisconnect = false
        session.connectionPassword = password
        session.reconnectState = isReconnect ? session.reconnectState : .idle
        session.status = isReconnect ? .reconnecting : .connecting
        session.shouldRestoreConnectionOnForeground = true
        session.remoteControlUnsupportedMessage = nil
        session.remotePointerOverlayState = .hidden
        session.remoteControlKeyboardFocused = shouldShowRemoteTrackpad(for: session)
        persistSessions()
        notifySessionChanges()

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

            bindResize(for: surface, bridge: bridge, session: session)

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
            session.shouldRestoreConnectionOnForeground = true
            if session.profile.authMethod == .password, let password, !password.isEmpty {
                try? credentialStore.storePassword(password, for: session.profile.id)
            }
            persistSessions()
            notifySessionChanges()
            return true
        } catch {
            await teardownRemoteResources(for: session)
            session.remoteControlKeyboardFocused = false
            if isReconnect {
                session.status = .reconnecting
            } else {
                session.status = .failed(error.localizedDescription)
            }
            persistSessions()
            notifySessionChanges()
            return false
        }
    }

    private func reconnectSession(sessionID: UUID) async -> Result<Void, SSHReconnectManager.ReconnectError> {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return .failure(.permanent("Session not found"))
        }
        if session.connectionPassword == nil, session.profile.authMethod == .password {
            session.connectionPassword = credentialStore.password(for: session.profile.id)
        }
        guard prepareSurface(for: session) else {
            return .failure(.transient("Surface preparation failed"))
        }
        let success = await establishConnection(
            for: session,
            password: session.connectionPassword,
            isReconnect: true
        )
        return success ? .success(()) : .failure(.transient(session.connectionErrorMessage ?? "Connection failed"))
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
        case .permanentFailure(let reason):
            session.reconnectState = .gaveUp(attempts: 0)
            session.status = .failed(reason)
        }
        persistSessions()
        notifySessionChanges()
    }

    private func refreshReconnectManager() {
        reconnectManager = SSHReconnectManager(
            config: Self.reconnectConfig(from: appSettings)
        )
    }

    private func persistSessions() {
        guard !sessions.isEmpty || activeSessionID != nil || externalDisplaySessionID != nil else {
            persistenceStore.clear()
            return
        }

        let snapshot = PersistedSessionSnapshot(
            sessions: sessions.map(Self.persistedDescriptor(from:)),
            activeSessionID: activeSessionID,
            externalDisplaySessionID: externalDisplaySessionID
        )
        persistenceStore.saveSnapshot(snapshot)
    }

    private func notifySessionChanges() {
        lifecycleDelegate?.sessionManagerDidChangeSessions(self)
    }

    static func reconnectConfig(from appSettings: AppSettings) -> SSHReconnectManager.Config {
        SSHReconnectManager.Config(
            enabled: appSettings.autoReconnect,
            maxAttempts: max(1, appSettings.maxReconnectAttempts),
            initialDelay: max(0.5, appSettings.reconnectDelay),
            maxDelay: max(1.0, appSettings.reconnectDelay * 4),
            backoffMultiplier: 2.0
        )
    }

    private static func persistedDescriptor(from session: SSHSessionModel) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: session.id,
            profile: session.profile,
            status: persistedStatus(from: session.status),
            connectedAt: session.connectedAt,
            reconnectState: persistedReconnectState(from: session.reconnectState),
            terminalTitle: session.terminalTitle,
            terminalSize: session.terminalSize,
            terminalPixelSize: session.terminalPixelSize,
            scrollbackLines: session.scrollbackLines,
            shouldRestoreConnectionOnForeground: session.shouldRestoreConnectionOnForeground,
            isOnExternalDisplay: session.isOnExternalDisplay
        )
    }

    private static func session(from descriptor: PersistedSessionDescriptor) -> SSHSessionModel {
        let session = SSHSessionModel(id: descriptor.id, profile: descriptor.profile)
        let shouldRestoreConnectionOnForeground =
            descriptor.shouldRestoreConnectionOnForeground
            || descriptor.status.requiresLiveResources
        session.status = sessionStatus(
            from: descriptor.status,
            shouldRestore: shouldRestoreConnectionOnForeground
        )
        session.connectedAt = descriptor.connectedAt
        session.reconnectState = reconnectState(from: descriptor.reconnectState)
        session.terminalTitle = descriptor.terminalTitle
        session.terminalSize = descriptor.terminalSize
        session.terminalPixelSize = descriptor.terminalPixelSize
        session.scrollbackLines = descriptor.scrollbackLines
        session.shouldRestoreConnectionOnForeground = shouldRestoreConnectionOnForeground
        session.isOnExternalDisplay = descriptor.isOnExternalDisplay
        session.wasRestoredFromPersistence = true
        return session
    }

    private static func persistedStatus(from status: SSHSessionModel.SessionStatus) -> PersistedSessionDescriptor.Status {
        switch status {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .authenticating:
            return .authenticating
        case .connected:
            return .connected
        case .reconnecting:
            return .reconnecting
        case .failed(let message):
            return .failed(message)
        }
    }

    private static func sessionStatus(
        from status: PersistedSessionDescriptor.Status,
        shouldRestore: Bool
    ) -> SSHSessionModel.SessionStatus {
        if shouldRestore, status.requiresLiveResources {
            return .reconnecting
        }

        switch status {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .disconnected
        case .authenticating:
            return .disconnected
        case .connected:
            return .disconnected
        case .reconnecting:
            return .disconnected
        case .failed(let message):
            return .failed(message)
        }
    }

    private static func persistedReconnectState(
        from reconnectState: SSHSessionModel.ReconnectState
    ) -> PersistedReconnectState {
        switch reconnectState {
        case .idle:
            return .idle
        case .attempting(let attempt, let maxAttempts):
            return .attempting(attempt: attempt, maxAttempts: maxAttempts)
        case .reconnected:
            return .reconnected
        case .gaveUp(let attempts):
            return .gaveUp(attempts: attempts)
        }
    }

    private static func reconnectState(
        from reconnectState: PersistedReconnectState
    ) -> SSHSessionModel.ReconnectState {
        switch reconnectState {
        case .idle:
            return .idle
        case .attempting(let attempt, let maxAttempts):
            return .attempting(attempt: attempt, maxAttempts: maxAttempts)
        case .reconnected:
            return .reconnected
        case .gaveUp(let attempts):
            return .gaveUp(attempts: attempts)
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

private extension PersistedSessionDescriptor.Status {
    var requiresLiveResources: Bool {
        switch self {
        case .connecting, .authenticating, .connected, .reconnecting:
            true
        case .disconnected, .failed:
            false
        }
    }
}
