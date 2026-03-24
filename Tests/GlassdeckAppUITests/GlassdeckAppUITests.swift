import XCTest

@MainActor
final class GlassdeckAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmptyLaunchShowsConnectionsRoot() {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.navigationBars["Connections"].firstMatch.waitForExistence(timeout: UITestTimeout.short))
        XCTAssertTrue(app.staticTexts["No Connections"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Connections"].firstMatch.exists)
    }

    func testNewConnectionSheetPresentsFromConnections() {
        let app = launchApp(scenario: "connections")

        app.buttons["new-connection-button"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["New Connection"].firstMatch.waitForExistence(timeout: UITestTimeout.short))
        XCTAssertTrue(app.textFields["connection-name-field"].firstMatch.exists)
        XCTAssertTrue(app.textFields["connection-host-field"].firstMatch.exists)
        XCTAssertTrue(app.textFields["connection-username-field"].firstMatch.exists)
        XCTAssertTrue(app.buttons["connection-save-button"].firstMatch.exists)
    }

    func testSessionRowTapNavigatesToDetail() {
        let app = launchApp(scenario: "sessions")

        let sessionsTab = app.tabBars.buttons["Sessions"].firstMatch
        XCTAssertTrue(sessionsTab.waitForExistence(timeout: UITestTimeout.short))
        sessionsTab.tap()

        let sessionRow = app.descendants(matching: .any)
            .matching(identifier: "session-card-11111111-1111-1111-1111-111111111111")
            .firstMatch
        XCTAssertTrue(sessionRow.waitForExistence(timeout: UITestTimeout.standard))

        sessionRow.tap()

        XCTAssertTrue(app.otherElements["session-detail-view"].firstMatch.waitForExistence(timeout: UITestTimeout.standard))
        XCTAssertTrue(app.buttons["session-menu-button"].firstMatch.exists)
    }

    func testSessionScenarioTerminalScreenshotIsNotBlank() {
        let app = launchApp(
            scenario: "sessions",
            openActiveSession: true,
            additionalArguments: ["-uiTestRequirePreviewSurface"]
        )

        XCTAssertTrue(app.otherElements["session-detail-view"].firstMatch.waitForExistence(timeout: UITestTimeout.long))
        waitForTerminalRenderSummary(
            containingAnyOf: ["GLASSDECK_SSH_OK", "preview.txt", "/home/glassdeck"],
            in: app
        )

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        assertScreenshotIsNotBlank(
            of: terminalSurface,
            named: "session-terminal-surface"
        )
    }

    func testSessionScenarioHonorsSeededLightTerminalTheme() {
        let app = launchApp(
            scenario: "sessions",
            openActiveSession: true,
            additionalArguments: ["-uiTestRequirePreviewSurface"],
            additionalEnvironment: [
                "GLASSDECK_UI_TEST_TERMINAL_COLOR_SCHEME": "Default Light"
            ]
        )

        XCTAssertTrue(app.otherElements["session-detail-view"].firstMatch.waitForExistence(timeout: UITestTimeout.long))
        waitForTerminalRenderSummary(
            containingAnyOf: ["GLASSDECK_SSH_OK", "preview.txt", "/home/glassdeck"],
            in: app
        )

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        assertScreenshotHasAverageBrightness(
            of: terminalSurface,
            named: "session-terminal-light-theme",
            minimumAverageBrightness: 150
        )
    }

    func testAnimationScenarioAdvancesFramesAndRendersTerminal() {
        let app = launchApp(
            scenario: "animation",
            openActiveSession: true,
            additionalEnvironment: [
                "GLASSDECK_UI_TEST_ANIMATION_FRAMES_PATH": homeAnimationFramesPath()
            ]
        )

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: UITestTimeout.standard))
        // The animation loops through 235 frames (0–234) at ~31ms each (~7.3s per
        // cycle).  Verify the player is running by confirming the frame counter
        // changes between snapshots.  We use a fixed low threshold for the first
        // check (startFrameIndex is 16) so the target is always reachable even
        // after a frame-index wrap.
        let firstFrame = waitForAnimationProgress(pastFrame: 20, in: app)
        XCTAssertGreaterThan(firstFrame, 20)

        Thread.sleep(forTimeInterval: 0.5)

        let secondFrame = currentAnimationFrame(in: app)
        XCTAssertNotEqual(secondFrame, firstFrame, "Animation should be advancing frames")

        Thread.sleep(forTimeInterval: 0.5)

        let thirdFrame = currentAnimationFrame(in: app)
        XCTAssertNotEqual(thirdFrame, secondFrame, "Animation should continue advancing")

        assertScreenshotIsNotBlank(
            of: terminalSurface,
            named: "animation-terminal-surface"
        )
    }

    func testRemoteScenarioAutoEntersTrackpadView() {
        let app = launchApp(scenario: "remote", openActiveSession: true)

        XCTAssertTrue(app.otherElements["remote-trackpad-view"].firstMatch.waitForExistence(timeout: UITestTimeout.short))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testRemoteScenarioDoesNotOfferLocalTerminalOverride() {
        let app = launchApp(scenario: "remote", openActiveSession: true)

        let menuButton = app.buttons["session-menu-button"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestTimeout.standard))
        menuButton.tap()

        XCTAssertFalse(app.buttons["View Local Terminal"].firstMatch.exists)
    }

    func testSessionScenarioCanToggleTerminalKeyboardFromTap() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: UITestTimeout.standard))
        waitForTerminalKeyboardState(presented: false, in: app)

        terminalSurface.tap()
        waitForTerminalKeyboardState(presented: true, in: app)

        terminalSurface.tap()
        waitForTerminalKeyboardState(presented: false, in: app)
    }

    func testSessionScenarioKeyboardHostTapDoesNotHidePresentedKeyboard() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: UITestTimeout.standard))
        waitForTerminalKeyboardState(presented: false, in: app)

        terminalSurface.tap()
        waitForTerminalKeyboardState(presented: true, in: app)

        let keyboardHost = app.descendants(matching: .any)
            .matching(identifier: "session-keyboard-host")
            .firstMatch
        XCTAssertTrue(keyboardHost.waitForExistence(timeout: UITestTimeout.standard))

        keyboardHost.tap()
        waitForTerminalKeyboardState(presented: true, in: app)
    }

    func testSessionScenarioExposesSeparateKeyboardStateElement() {
        let app = launchApp(
            scenario: "sessions",
            openActiveSession: true,
            additionalArguments: ["-uiTestExposeTerminalRenderSummary"]
        )

        let keyboardHost = app.textFields["session-keyboard-host"].firstMatch
        XCTAssertTrue(keyboardHost.waitForExistence(timeout: UITestTimeout.standard))

        let keyboardState = app.otherElements["session-keyboard-state"].firstMatch
        XCTAssertTrue(keyboardState.waitForExistence(timeout: UITestTimeout.standard))
        XCTAssertEqual((keyboardState.value as? String) ?? keyboardState.label, "hidden")

        let hostValue = keyboardHost.value as? String
        XCTAssertNotEqual(hostValue, "hidden")
        XCTAssertNotEqual(hostValue, "presented")
    }

    func testSSHKeysSheetShowsEmptyStateWhenNoKeysExist() {
        let app = launchApp(scenario: "connections")

        app.buttons["connections-toolbar-menu"].firstMatch.tap()
        app.buttons["connections-menu-ssh-keys"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["SSH Keys"].firstMatch.waitForExistence(timeout: UITestTimeout.standard))
        XCTAssertTrue(app.staticTexts["No Stored Keys"].firstMatch.waitForExistence(timeout: UITestTimeout.standard))
        XCTAssertFalse(app.staticTexts["Stored Keys"].firstMatch.exists)
    }

    func testTerminalSettingsExposeIndependentIPhoneAndExternalMonitorProfiles() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        let menuButton = app.buttons["session-menu-button"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestTimeout.standard))
        menuButton.tap()
        app.buttons["Settings"].firstMatch.tap()

        let targetPicker = app.segmentedControls["terminal-settings-target-picker"].firstMatch
        XCTAssertTrue(targetPicker.waitForExistence(timeout: UITestTimeout.standard))

        let profileSummary = app.otherElements["terminal-settings-profile-summary"].firstMatch
        XCTAssertTrue(profileSummary.waitForExistence(timeout: UITestTimeout.standard))
        let iphoneProfileSummary = profileSummary.value as? String

        targetPicker.buttons["External Monitor"].firstMatch.tap()
        let externalProfileSummary = profileSummary.value as? String
        XCTAssertNotEqual(externalProfileSummary, iphoneProfileSummary)

        targetPicker.buttons["iPhone"].firstMatch.tap()
        XCTAssertEqual(profileSummary.value as? String, iphoneProfileSummary)
    }

    func testAnimationScenarioDoesNotLeakDarkOverlayIntoConnectionsTab() {
        let app = launchUITestApp(
            scenario: "animation",
            additionalEnvironment: [
                "GLASSDECK_UI_TEST_ANIMATION_FRAMES_PATH": homeAnimationFramesPath()
            ]
        )

        let sessionsTab = app.tabBars.buttons["Sessions"].firstMatch
        XCTAssertTrue(sessionsTab.waitForExistence(timeout: UITestTimeout.long))
        sessionsTab.tap()
        let animationSessionCard = app.descendants(matching: .any)
            .matching(identifier: "session-card-55555555-5555-5555-5555-555555555555")
            .firstMatch
        XCTAssertTrue(animationSessionCard.waitForExistence(timeout: UITestTimeout.long))

        app.tabBars.buttons["Connections"].firstMatch.tap()

        let connectionRow = app.buttons[
            connectionRowIdentifier(name: "Glassdeck Test SSH", host: "glassdeck-test.local")
        ].firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: UITestTimeout.long))
        assertScreenHasAverageBrightness(
            named: "connections-after-animation-switch",
            minimumAverageBrightness: 120
        )
    }

    func testSessionDetailDoesNotExposeLegacyFilesSheet() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        XCTAssertTrue(app.otherElements["session-detail-view"].firstMatch.waitForExistence(timeout: UITestTimeout.long))
        XCTAssertFalse(app.buttons["session-files-button"].firstMatch.exists)
    }

    @discardableResult
    private func launchApp(
        scenario: String,
        openActiveSession: Bool = false,
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestScenario",
            scenario,
            "-uiTestDisableAnimations",
            "-uiTestExposeTerminalRenderSummary"
        ]
        if openActiveSession {
            app.launchArguments.append("-uiTestOpenActiveSession")
        }
        app.launchArguments.append(contentsOf: additionalArguments)
        app.launchEnvironment.merge(uiTestFilesystemEnvironment()) { current, _ in current }
        app.launchEnvironment.merge(additionalEnvironment) { _, new in new }
        app.launch()
        return app
    }
}
