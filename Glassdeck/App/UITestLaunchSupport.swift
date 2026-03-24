import Foundation
import GlassdeckCore
import UIKit

@MainActor
enum UITestLaunchSupport {
    enum Scenario: String {
        case empty
        case connections
        case sessions
        case remote
        case animation
    }

    private static let previewTerminalMarker = "GLASSDECK_KEY_OK"
    private static let remotePreviewTerminalMarker = "GLASSDECK_PASSWORD_OK"
    private static let animationFramesEnvironmentKey = "GLASSDECK_UI_TEST_ANIMATION_FRAMES_PATH"
    private static let terminalColorSchemeEnvironmentKey = "GLASSDECK_UI_TEST_TERMINAL_COLOR_SCHEME"
    private static let preserveHostStateEnvironmentKey = "GLASSDECK_UI_TEST_PRESERVE_HOST_STATE"
    private static let seedLiveSSHSessionEnvironmentKey = "GLASSDECK_UI_TEST_SEED_LIVE_SSH_SESSION"
    private static let seedLiveSSHNameEnvironmentKey = "GLASSDECK_UI_TEST_SEED_LIVE_SSH_NAME"
    private static let connectedTerminalCommandEnvironmentKey = "GLASSDECK_UI_TEST_CONNECTED_TERMINAL_COMMAND_BASE64"
    private static let hostBackedLaunchRoutingStateDefaultsKey = "glassdeck.ui-test.launch-routing-state"
    private static let deferredLiveSSHResumeSessionDefaultsKey = "glassdeck.ui-test.deferred-live-ssh-session-id"
    private static var activeAnimationPlayer: GhosttyHomeAnimationPlayer?

    enum HostBackedLaunchState: String {
        case unavailable
        case waitingForSession
        case waitingForRouteableSession
        case routeApplied
        case noRouteableSession
    }

    static var currentScenario: Scenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let scenarioIndex = arguments.firstIndex(of: "-uiTestScenario"),
            arguments.indices.contains(arguments.index(after: scenarioIndex))
        else {
            return nil
        }

        return Scenario(rawValue: arguments[arguments.index(after: scenarioIndex)])
    }

    static var exposesTerminalRenderSummary: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestExposeTerminalRenderSummary")
    }

    static var requiresPreviewSurface: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestRequirePreviewSurface")
    }

    static var isPreservingHostState: Bool {
        ProcessInfo.processInfo.environment[preserveHostStateEnvironmentKey] == "1"
    }

    static var shouldRouteAfterPreservedHostState: Bool {
        isPreservingHostState && ProcessInfo.processInfo.arguments.contains("-uiTestOpenActiveSession")
    }

    static var launchRoutingState: HostBackedLaunchState {
        launchRoutingState()
    }

    static func launchRoutingState(defaults: UserDefaults = .standard) -> HostBackedLaunchState {
        HostBackedLaunchState(rawValue: defaults.string(forKey: hostBackedLaunchRoutingStateDefaultsKey) ?? "")
            ?? .unavailable
    }

    static func setLaunchRoutingState(_ state: HostBackedLaunchState, defaults: UserDefaults = .standard) {
        defaults.set(state.rawValue, forKey: hostBackedLaunchRoutingStateDefaultsKey)
    }

    static func clearLaunchRoutingState(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: hostBackedLaunchRoutingStateDefaultsKey)
    }

    static func storeDeferredLiveSSHResumeSessionID(
        _ sessionID: UUID?,
        defaults: UserDefaults = .standard
    ) {
        guard let sessionID else {
            defaults.removeObject(forKey: deferredLiveSSHResumeSessionDefaultsKey)
            return
        }

        defaults.set(sessionID.uuidString, forKey: deferredLiveSSHResumeSessionDefaultsKey)
    }

    @discardableResult
    static func prepareDeferredLiveSSHResumeIfNeeded(
        sessionManager: SessionManager,
        defaults: UserDefaults = .standard
    ) -> SSHSessionModel? {
        guard
            let rawSessionID = defaults.string(forKey: deferredLiveSSHResumeSessionDefaultsKey),
            let sessionID = UUID(uuidString: rawSessionID),
            let session = sessionManager.session(with: sessionID)
        else {
            defaults.removeObject(forKey: deferredLiveSSHResumeSessionDefaultsKey)
            return nil
        }

        defaults.removeObject(forKey: deferredLiveSSHResumeSessionDefaultsKey)
        session.shouldRestoreConnectionOnForeground = true
        return session
    }

    static func resumeDeferredLiveSSHSeedIfNeeded(sessionManager: SessionManager) {
        guard prepareDeferredLiveSSHResumeIfNeeded(sessionManager: sessionManager) != nil else {
            return
        }

        Task { @MainActor in
            // Give SwiftUI one more turn to mount the routed session detail view
            // before reconnecting and preparing the live surface.
            await Task.yield()
            sessionManager.resumeRestorableSessionsIfNeeded()
        }
    }

    static func configureIfNeeded(
        sessionManager: SessionManager,
        connectionStore: ConnectionStore,
        appSettings: AppSettings
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestDisableAnimations") {
            UserDefaults.standard.set(false, forKey: "UIViewAnimationEnabled")
        }

        sessionManager.setUITestConnectedCommand(connectedTerminalCommand())

        if let liveSSHSeed = LiveSSHSeed.load() {
            resetPersistentTestState()
            seedClipboardIfNeeded()
            appSettings.resetTerminalConfig()
            appSettings.remoteTrackpadLastMode = .cursor
            applyTerminalSettingsOverrides(appSettings)
            applyLiveSSHSeed(
                liveSSHSeed,
                sessionManager: sessionManager,
                connectionStore: connectionStore
            )
        }

        if isPreservingHostState {
            clearLaunchRoutingState()
            setLaunchRoutingState(.waitingForSession)
            return
        }

        guard let scenario = currentScenario else {
            return
        }

        resetPersistentTestState()
        seedClipboardIfNeeded()
        appSettings.resetTerminalConfig()
        appSettings.remoteTrackpadLastMode = .cursor
        applyTerminalSettingsOverrides(appSettings)

        switch scenario {
        case .empty:
            connectionStore.replaceAll(with: [])
            sessionManager.replaceSessionsForPreview(
                [],
                activeSessionID: nil,
                externalDisplaySessionID: nil,
                hasExternalDisplayConnected: false
            )
        case .connections:
            connectionStore.replaceAll(with: previewConnections())
            sessionManager.replaceSessionsForPreview(
                [],
                activeSessionID: nil,
                externalDisplaySessionID: nil,
                hasExternalDisplayConnected: false
            )
        case .sessions:
            let connections = previewConnections()
            let sessions = previewSessions(using: connections, sessionManager: sessionManager)
            connectionStore.replaceAll(with: connections)
            sessionManager.replaceSessionsForPreview(
                sessions,
                activeSessionID: sessions.first?.id,
                externalDisplaySessionID: nil,
                hasExternalDisplayConnected: false
            )
        case .remote:
            let connections = previewConnections()
            let session = previewRemoteSession(using: connections[0], sessionManager: sessionManager)
            connectionStore.replaceAll(with: connections)
            sessionManager.replaceSessionsForPreview(
                [session],
                activeSessionID: session.id,
                externalDisplaySessionID: session.id,
                hasExternalDisplayConnected: true
            )
        case .animation:
            let connection = previewConnections()[0]
            let session = previewAnimationSession(
                using: connection,
                sessionManager: sessionManager
            )
            connectionStore.replaceAll(with: [connection])
            // Align app settings with the animation terminal configuration so that
            // replaceSessionsForPreview → prepareSurface does not recreate the surface
            // (a replacement surface starts with zero metrics, preventing routing).
            appSettings.setTerminalConfig(
                GhosttyHomeAnimationSequence.testingTerminalConfiguration,
                for: .iphone
            )
            sessionManager.replaceSessionsForPreview(
                [session],
                activeSessionID: session.id,
                externalDisplaySessionID: nil,
                hasExternalDisplayConnected: false
            )
            startAnimationPlaybackIfPossible(for: session)
        }
    }

    private static func previewConnections() -> [ConnectionProfile] {
        [
            ConnectionProfile(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID(),
                name: "Glassdeck Test SSH",
                host: "glassdeck-test.local",
                username: "glassdeck",
                authMethod: .sshKey,
                sshKeyID: "glassdeck-docker",
                notes: AttributedString("Local Docker SSH target."),
                lastConnected: .now.addingTimeInterval(-900)
            ),
            ConnectionProfile(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID(),
                name: "Production",
                host: "prod.example.com",
                username: "deploy",
                authMethod: .sshKey,
                sshKeyID: "prod",
                lastConnected: .now.addingTimeInterval(-3600)
            ),
            ConnectionProfile(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC") ?? UUID(),
                name: "Docs Box",
                host: "10.42.0.20",
                username: "docs",
                authMethod: .password,
                lastConnected: .now.addingTimeInterval(-86_400)
            ),
            ConnectionProfile(
                id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD") ?? UUID(),
                name: "Homelab NAS",
                host: "nas.local",
                username: "storage",
                authMethod: .sshKey,
                sshKeyID: "nas"
            )
        ]
    }

    private static func previewSessions(
        using connections: [ConnectionProfile],
        sessionManager: SessionManager
    ) -> [SSHSessionModel] {
        let active = connectedPreviewSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            profile: connections[0],
            sessionManager: sessionManager,
            connectedAt: .now.addingTimeInterval(-1200),
            terminalTitle: "glassdeck@test-ssh",
            transcriptMarker: previewTerminalMarker,
            terminalSize: TerminalSize(columns: 118, rows: 29),
            terminalPixelSize: TerminalPixelSize(width: 1290, height: 880),
            scrollbackLines: 814
        )

        let reconnecting = SSHSessionModel(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            profile: connections[1]
        )
        reconnecting.status = .reconnecting
        reconnecting.connectedAt = .now.addingTimeInterval(-7200)
        reconnecting.reconnectState = .attempting(attempt: 2, maxAttempts: 5)
        reconnecting.terminalTitle = "deploy@production"
        reconnecting.terminalSize = TerminalSize(columns: 104, rows: 28)
        reconnecting.scrollbackLines = 421

        let inactive = SSHSessionModel(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            profile: connections[2]
        )
        inactive.status = .failed("Host key changed")
        inactive.connectedAt = .now.addingTimeInterval(-18_000)
        inactive.terminalTitle = "docs@box"
        inactive.terminalSize = TerminalSize(columns: 96, rows: 26)

        return [active, reconnecting, inactive]
    }

    private static func previewRemoteSession(
        using profile: ConnectionProfile,
        sessionManager: SessionManager
    ) -> SSHSessionModel {
        let interactionGeometry = RemoteTerminalGeometry(
            terminalSize: TerminalSize(columns: 120, rows: 30),
            surfacePixelSize: TerminalPixelSize(width: 1440, height: 900),
            cellPixelSize: TerminalPixelSize(width: 12, height: 24),
            padding: RemoteControlInsets(top: 18, left: 18, bottom: 18, right: 18),
            displayScale: 2
        )
        let interactionCapabilities = GhosttyVTInteractionCapabilities(
            supportsMousePlacement: true,
            supportsScrollReporting: true
        )

        let session = connectedPreviewSession(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
            profile: profile,
            sessionManager: sessionManager,
            connectedAt: .now.addingTimeInterval(-300),
            terminalTitle: "glassdeck@test-ssh",
            transcriptMarker: remotePreviewTerminalMarker,
            terminalSize: TerminalSize(columns: 120, rows: 30),
            terminalPixelSize: TerminalPixelSize(width: 1440, height: 900),
            scrollbackLines: 233,
            interactionGeometry: interactionGeometry,
            interactionCapabilities: interactionCapabilities
        )
        return session
    }

    private static func previewAnimationSession(
        using profile: ConnectionProfile,
        sessionManager: SessionManager
    ) -> SSHSessionModel {
        let session = SSHSessionModel(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
            profile: profile
        )
        session.status = .connected
        session.connectedAt = .now.addingTimeInterval(-31)

        let didSeedSurface = sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "Ghostty Home Animation",
                transcript: "",
                terminalConfiguration: GhosttyHomeAnimationSequence.testingTerminalConfiguration,
                terminalMetricsPreset: GhosttyHomeAnimationSequence.testingMetricsPreset,
                terminalSize: TerminalSize(
                    columns: GhosttyHomeAnimationSequence.expectedColumns,
                    rows: GhosttyHomeAnimationSequence.expectedRows
                ),
                terminalPixelSize: nil,
                scrollbackLines: GhosttyHomeAnimationSequence.expectedFrameCount * GhosttyHomeAnimationSequence.expectedRows
            )
        )
        assert(
            didSeedSurface,
            "Animation preview sessions must have a synthetic GhosttySurface."
        )
        return session
    }

    private static func connectedPreviewSession(
        id: UUID,
        profile: ConnectionProfile,
        sessionManager: SessionManager,
        connectedAt: Date,
        terminalTitle: String,
        transcriptMarker: String,
        terminalSize: TerminalSize,
        terminalPixelSize: TerminalPixelSize?,
        scrollbackLines: Int,
        interactionGeometry: RemoteTerminalGeometry? = nil,
        interactionCapabilities: GhosttyVTInteractionCapabilities? = nil
    ) -> SSHSessionModel {
        let session = SSHSessionModel(id: id, profile: profile)
        session.status = .connected
        session.connectedAt = connectedAt

        sessionManager.primeSyntheticPreviewSession(
            session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: terminalTitle,
                transcript: previewTranscript(marker: transcriptMarker, profile: profile),
                terminalSize: terminalSize,
                terminalPixelSize: terminalPixelSize,
                scrollbackLines: scrollbackLines,
                interactionGeometry: interactionGeometry,
                interactionCapabilities: interactionCapabilities
            )
        )
        return session
    }

    private static func previewTranscript(marker: String, profile: ConnectionProfile) -> String {
        [
            "\(profile.username)@\(profile.host):~$ echo \(marker) && pwd && ls ~/testdata && ~/bin/health-check.sh",
            marker,
            "/home/\(profile.username)",
            "nested",
            "nano-target.txt",
            "preview.txt",
            "GLASSDECK_SSH_OK",
            "/home/\(profile.username)",
            "nested",
            "nano-target.txt",
            "preview.txt",
            "\(profile.username)@\(profile.host):~$"
        ]
        .joined(separator: "\n")
        .appending("\n")
    }

    private static func applyLiveSSHSeed(
        _ seed: LiveSSHSeed,
        sessionManager: SessionManager,
        connectionStore: ConnectionStore
    ) {
        if let keyData = seed.privateKeyData, let keyID = seed.profile.sshKeyID {
            SSHKeyManager.shared.savePrivateKey(id: keyID, keyData: keyData)
        }

        if let password = seed.password, !password.isEmpty {
            try? SessionCredentialStore().storePassword(password, for: seed.profile.id)
        }

        connectionStore.replaceAll(with: [seed.profile])
        sessionManager.replaceSessionsFromPersistedSnapshot(
            seed.snapshot,
            prepareSurfaces: false
        )
        if let session = sessionManager.activeSession ?? sessionManager.sessions.first {
            sessionManager.primeSyntheticPreviewSession(
                session,
                seed: SessionManager.SyntheticTerminalSeed(
                    title: "\(seed.profile.username)@\(seed.profile.host)",
                    transcript: previewTranscript(marker: previewTerminalMarker, profile: seed.profile),
                    terminalSize: TerminalSize(columns: 80, rows: 24),
                    scrollbackLines: 6
                )
            )
            let shouldResumeLiveConnection = session.shouldRestoreConnectionOnForeground
            session.shouldRestoreConnectionOnForeground = false
            storeDeferredLiveSSHResumeSessionID(
                shouldResumeLiveConnection ? session.id : nil
            )
        }
    }

    private static func resetPersistentTestState() {
        activeAnimationPlayer?.stop()
        activeAnimationPlayer = nil
        SessionPersistenceStore().clear()
        SessionCredentialStore().removeAll()
        HostKeyVerifier.clearAllKnownHosts()
        UserDefaults.standard.removeObject(forKey: "glassdeck.known-hosts")
        storeDeferredLiveSSHResumeSessionID(nil)
        for keyID in SSHKeyManager.shared.listKeys() {
            try? SSHKeyManager.shared.deleteKey(id: keyID)
        }
    }

    private static func startAnimationPlaybackIfPossible(for session: SSHSessionModel) {
        guard let surface = session.surface else {
            session.status = .failed("Animation scenario is missing a terminal surface.")
            return
        }

        guard let framesPath = ProcessInfo.processInfo.environment[animationFramesEnvironmentKey], !framesPath.isEmpty else {
            session.status = .failed("Set \(animationFramesEnvironmentKey) to launch the animation scenario.")
            return
        }

        do {
            let sequence = try GhosttyHomeAnimationSequence.load(
                from: URL(fileURLWithPath: framesPath, isDirectory: true)
            )
            let player = GhosttyHomeAnimationPlayer(surface: surface, sequence: sequence)
            activeAnimationPlayer = player
            try player.start()
        } catch {
            session.status = .failed(error.localizedDescription)
        }
    }

    private static func seedClipboardIfNeeded() {
        guard
            let encoded = ProcessInfo.processInfo.environment["GLASSDECK_UI_TEST_CLIPBOARD_TEXT_BASE64"],
            let data = Data(base64Encoded: encoded),
            let string = String(data: data, encoding: .utf8)
        else {
            return
        }

        UIPasteboard.general.string = string
    }

    private static func applyTerminalSettingsOverrides(_ appSettings: AppSettings) {
        guard
            let rawValue = ProcessInfo.processInfo.environment[terminalColorSchemeEnvironmentKey],
            let scheme = TerminalColorScheme(rawValue: rawValue)
        else {
            return
        }

        var iphoneConfiguration = appSettings.terminalConfig(for: .iphone)
        iphoneConfiguration.colorScheme = scheme
        appSettings.setTerminalConfig(iphoneConfiguration, for: .iphone)

        var externalMonitorConfiguration = appSettings.terminalConfig(for: .externalMonitor)
        externalMonitorConfiguration.colorScheme = scheme
        appSettings.setTerminalConfig(externalMonitorConfiguration, for: .externalMonitor)
    }

    private static func connectedTerminalCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard
            let encoded = environment[connectedTerminalCommandEnvironmentKey],
            let data = Data(base64Encoded: encoded),
            let command = String(data: data, encoding: .utf8),
            !command.isEmpty
        else {
            return nil
        }

        return command
    }

    private struct LiveSSHSeed {
        private static let seededProfileID = UUID(uuidString: "99999999-1111-1111-1111-111111111111") ?? UUID()
        private static let seededSessionID = UUID(uuidString: "99999999-2222-2222-2222-222222222222") ?? UUID()
        private static let seededSSHKeyID = "glassdeck-ui-test-live-ssh"

        let profile: ConnectionProfile
        let snapshot: PersistedSessionSnapshot
        let password: String?
        let privateKeyData: Data?

        @MainActor
        static func load(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> LiveSSHSeed? {
            guard environment[seedLiveSSHSessionEnvironmentKey] == "1" else {
                return nil
            }

            guard
                environment["GLASSDECK_LIVE_SSH_ENABLED"] == "1",
                let host = environment["GLASSDECK_LIVE_SSH_HOST"],
                let portString = environment["GLASSDECK_LIVE_SSH_PORT"],
                let port = Int(portString),
                let username = environment["GLASSDECK_LIVE_SSH_USER"]
            else {
                return nil
            }

            let privateKeyData = environment["GLASSDECK_UI_TEST_CLIPBOARD_TEXT_BASE64"]
                .flatMap { Data(base64Encoded: $0) }
            let usesSSHKey = privateKeyData?.isEmpty == false
            let authMethod: AuthMethod = usesSSHKey ? .sshKey : .password
            let connectionName = environment[seedLiveSSHNameEnvironmentKey] ?? "UITest Live SSH"
            let password = environment["GLASSDECK_LIVE_SSH_PASSWORD"]
            let profile = ConnectionProfile(
                id: seededProfileID,
                name: connectionName,
                host: host,
                port: port,
                username: username,
                authMethod: authMethod,
                sshKeyID: usesSSHKey ? seededSSHKeyID : nil,
                notes: AttributedString("UITest live SSH seed."),
                lastConnected: .now,
                createdAt: .now
            )

            let descriptor = PersistedSessionDescriptor(
                id: seededSessionID,
                profile: profile,
                status: .disconnected,
                connectedAt: .now,
                reconnectState: .idle,
                terminalTitle: "\(username)@\(host)",
                terminalSize: TerminalSize(columns: 80, rows: 24),
                terminalPixelSize: nil,
                scrollbackLines: 0,
                shouldRestoreConnectionOnForeground: true,
                isOnExternalDisplay: false
            )

            return LiveSSHSeed(
                profile: profile,
                snapshot: PersistedSessionSnapshot(
                    sessions: [descriptor],
                    activeSessionID: descriptor.id,
                    externalDisplaySessionID: nil
                ),
                password: authMethod == .password ? password : nil,
                privateKeyData: privateKeyData
            )
        }
    }
}
