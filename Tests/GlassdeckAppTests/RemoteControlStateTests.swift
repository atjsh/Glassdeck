import CoreGraphics
@testable import Glassdeck
import GlassdeckCore
import XCTest

@MainActor
final class RemoteControlStateTests: XCTestCase {
    func testRemoteTrackpadEligibilityRequiresConnectedExternalDisplayAndMatchingSession() {
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected

        XCTAssertTrue(SessionManager.remoteTrackpadEligibility(
            hasExternalDisplayConnected: true,
            activeSessionID: session.id,
            externalDisplaySessionID: session.id,
            session: session
        ))

        XCTAssertFalse(SessionManager.remoteTrackpadEligibility(
            hasExternalDisplayConnected: false,
            activeSessionID: session.id,
            externalDisplaySessionID: session.id,
            session: session
        ))

        XCTAssertFalse(SessionManager.remoteTrackpadEligibility(
            hasExternalDisplayConnected: true,
            activeSessionID: UUID(),
            externalDisplaySessionID: session.id,
            session: session
        ))

        session.remoteControlShowsLocalTerminal = true
        XCTAssertFalse(SessionManager.remoteTrackpadEligibility(
            hasExternalDisplayConnected: true,
            activeSessionID: session.id,
            externalDisplaySessionID: session.id,
            session: session
        ))
    }

    func testMouseModePersistsAndShowsVisiblePointer() {
        let appSettings = AppSettings()
        let session = configuredSession()
        let coordinator = RemoteTrackpadCoordinator()

        coordinator.bind(session: session, appSettings: appSettings)
        coordinator.setMode(.mouse)

        XCTAssertEqual(appSettings.remoteTrackpadLastMode, .mouse)
        XCTAssertEqual(session.remoteControlMode, .mouse)
        XCTAssertTrue(session.remotePointerOverlayState.isVisible)
        XCTAssertEqual(session.remotePointerOverlayState.mode, .mouse)
        XCTAssertEqual(session.remotePointerOverlayState.cellPosition, RemoteCellPosition(column: 40, row: 12))
    }

    func testCursorModeShowsUnsupportedMessageWhenPlacementUnavailable() {
        let appSettings = AppSettings()
        let session = configuredSession(supportsMousePlacement: false)
        let coordinator = RemoteTrackpadCoordinator()

        coordinator.bind(session: session, appSettings: appSettings)
        coordinator.setMode(.cursor)
        coordinator.primaryPanChanged(
            location: CGPoint(x: 120, y: 80),
            translation: .zero,
            in: CGSize(width: 300, height: 200)
        )

        XCTAssertEqual(session.remoteControlMode, .cursor)
        XCTAssertFalse(session.remotePointerOverlayState.isVisible)
        XCTAssertEqual(
            session.remoteControlUnsupportedMessage,
            "Cursor placement isn’t supported by the current terminal app."
        )
    }

    func testMousePanClampsPointerIntoViewport() {
        let appSettings = AppSettings()
        let session = configuredSession()
        let coordinator = RemoteTrackpadCoordinator()

        coordinator.bind(session: session, appSettings: appSettings)
        coordinator.setMode(.mouse)
        coordinator.primaryPanChanged(
            location: CGPoint(x: 0, y: 0),
            translation: CGPoint(x: 3_000, y: -3_000),
            in: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(session.remotePointerOverlayState.surfacePixelPoint.x, 809, accuracy: 0.5)
        XCTAssertEqual(session.remotePointerOverlayState.surfacePixelPoint.y, 10, accuracy: 0.5)
    }

    func testConnectedSurfaceInvariantRejectsConnectedSessionWithoutSurface() {
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected

        XCTAssertFalse(SessionManager.connectedSessionsHaveSurfaces([session]))
    }

    func testAttachSyntheticSurfaceForPreviewSeedsConnectedSessionState() {
        let sessionManager = SessionManager()
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected

        let didSeedSurface = sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "tester@example.com",
                transcript: [
                    "$ echo GLASSDECK_SSH_OK",
                    "GLASSDECK_SSH_OK",
                    "$ pwd",
                    "/home/tester",
                    "$"
                ].joined(separator: "\n"),
                terminalSize: TerminalSize(columns: 100, rows: 30),
                terminalPixelSize: TerminalPixelSize(width: 1200, height: 800),
                scrollbackLines: 12
            )
        )

        XCTAssertTrue(didSeedSurface)
        XCTAssertNotNil(session.surface)
        XCTAssertTrue(SessionManager.connectedSessionsHaveSurfaces([session]))
        XCTAssertEqual(session.terminalTitle, "tester@example.com")
        XCTAssertEqual(session.terminalSize, TerminalSize(columns: 100, rows: 30))
        XCTAssertEqual(session.terminalPixelSize, TerminalPixelSize(width: 1200, height: 800))
        XCTAssertEqual(session.scrollbackLines, 12)
    }

    func testSyntheticSurfaceUsesAppTerminalConfigurationByDefault() {
        let appSettings = AppSettings()
        appSettings.terminalConfig = TerminalConfiguration(
            fontSize: 19,
            colorScheme: .defaultLight,
            scrollbackLines: 24_000,
            cursorStyle: .bar,
            cursorBlink: false,
            bellSound: false
        )

        let sessionManager = SessionManager(appSettings: appSettings)
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected

        let didSeedSurface = sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "tester@example.com",
                transcript: "",
                terminalSize: TerminalSize(columns: 90, rows: 24)
            )
        )

        XCTAssertTrue(didSeedSurface)
        XCTAssertEqual(session.surface?.terminalConfiguration.fontSize, 19)
        XCTAssertEqual(session.surface?.terminalConfiguration.colorScheme, .defaultLight)
        XCTAssertEqual(session.surface?.terminalConfiguration.scrollbackLines, 24_000)
        XCTAssertEqual(session.surface?.terminalConfiguration.cursorStyle, .bar)
        XCTAssertEqual(session.surface?.terminalConfiguration.cursorBlink, false)
        XCTAssertEqual(session.surface?.terminalConfiguration.bellSound, false)
    }

    func testSyntheticSurfacePrefersExplicitSeedTerminalConfiguration() {
        let appSettings = AppSettings()
        appSettings.terminalConfig = TerminalConfiguration(colorScheme: .defaultLight)

        let sessionManager = SessionManager(appSettings: appSettings)
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected

        let seedConfiguration = TerminalConfiguration(
            fontSize: 12,
            colorScheme: .tokyoNight,
            scrollbackLines: 6_000,
            cursorStyle: .underline,
            cursorBlink: true,
            bellSound: true
        )

        let didSeedSurface = sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "preview",
                transcript: "",
                terminalConfiguration: seedConfiguration
            )
        )

        XCTAssertTrue(didSeedSurface)
        XCTAssertEqual(session.surface?.terminalConfiguration, seedConfiguration)
    }

    func testRecreatedSyntheticSurfaceUsesUpdatedAppTerminalConfiguration() {
        let appSettings = AppSettings()
        appSettings.terminalConfig = TerminalConfiguration(colorScheme: .defaultDark)

        let sessionManager = SessionManager(appSettings: appSettings)
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected

        XCTAssertTrue(sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "session",
                transcript: ""
            )
        ))
        let firstSurface = session.surface
        XCTAssertEqual(firstSurface?.terminalConfiguration.colorScheme, .defaultDark)

        session.surface = nil
        appSettings.terminalConfig = TerminalConfiguration(colorScheme: .defaultLight)

        XCTAssertTrue(sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "session",
                transcript: ""
            )
        ))

        XCTAssertNotNil(session.surface)
        XCTAssertFalse(firstSurface === session.surface)
        XCTAssertEqual(session.surface?.terminalConfiguration.colorScheme, .defaultLight)
    }

    private func configuredSession(
        supportsMousePlacement: Bool = true
    ) -> SSHSessionModel {
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected
        session.terminalInteractionGeometry = RemoteTerminalGeometry(
            terminalSize: TerminalSize(columns: 80, rows: 24),
            surfacePixelSize: TerminalPixelSize(width: 820, height: 500),
            cellPixelSize: TerminalPixelSize(width: 10, height: 20),
            padding: RemoteControlInsets(top: 10, left: 10, bottom: 10, right: 10),
            displayScale: 2
        )
        session.terminalInteractionCapabilities = GhosttyVTInteractionCapabilities(
            supportsMousePlacement: supportsMousePlacement,
            supportsScrollReporting: true
        )
        return session
    }

    private func sampleProfile() -> ConnectionProfile {
        ConnectionProfile(name: "Remote", host: "example.com", username: "tester")
    }
}
