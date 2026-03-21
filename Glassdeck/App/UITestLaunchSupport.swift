#if canImport(UIKit)
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
    }

    private static let previewTerminalMarker = "GLASSDECK_KEY_OK"
    private static let remotePreviewTerminalMarker = "GLASSDECK_PASSWORD_OK"

    static var exposesTerminalRenderSummary: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestExposeTerminalRenderSummary")
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

        guard
            let scenarioIndex = arguments.firstIndex(of: "-uiTestScenario"),
            arguments.indices.contains(arguments.index(after: scenarioIndex)),
            let scenario = Scenario(rawValue: arguments[arguments.index(after: scenarioIndex)])
        else {
            return
        }

        resetPersistentTestState()
        seedClipboardIfNeeded()
        appSettings.remoteTrackpadLastMode = .cursor

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
            if arguments.contains("-uiTestForceLocalTerminal") {
                session.remoteControlShowsLocalTerminal = true
            }
            connectionStore.replaceAll(with: connections)
            sessionManager.replaceSessionsForPreview(
                [session],
                activeSessionID: session.id,
                externalDisplaySessionID: session.id,
                hasExternalDisplayConnected: true
            )
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
        inactive.connectionError = "Host key changed"
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

        let didSeedSurface = sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
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
        assert(
            didSeedSurface,
            "Connected preview sessions must have a synthetic GhosttySurface."
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

    private static func resetPersistentTestState() {
        UserDefaults.standard.removeObject(forKey: "glassdeck.known-hosts")
        for keyID in SSHKeyManager.shared.listKeys() {
            try? SSHKeyManager.shared.deleteKey(id: keyID)
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
}
#endif
