import XCTest

@MainActor
final class GlassdeckAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmptyLaunchShowsConnectionsRoot() {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.navigationBars["Connections"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No Connections"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Connections"].firstMatch.exists)
    }

    func testNewConnectionSheetPresentsFromConnections() {
        let app = launchApp(scenario: "connections")

        app.buttons["new-connection-button"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["New Connection"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["connection-name-field"].firstMatch.exists)
        XCTAssertTrue(app.textFields["connection-host-field"].firstMatch.exists)
        XCTAssertTrue(app.textFields["connection-username-field"].firstMatch.exists)
        XCTAssertTrue(app.buttons["connection-save-button"].firstMatch.exists)
    }

    func testSessionRowTapNavigatesToDetail() {
        let app = launchApp(scenario: "sessions")

        let sessionsTab = app.tabBars.buttons["Sessions"].firstMatch
        XCTAssertTrue(sessionsTab.waitForExistence(timeout: 3))
        sessionsTab.tap()

        let sessionRow = app.descendants(matching: .any)
            .matching(identifier: "session-card-11111111-1111-1111-1111-111111111111")
            .firstMatch
        XCTAssertTrue(sessionRow.waitForExistence(timeout: 5))

        sessionRow.tap()

        XCTAssertTrue(app.buttons["session-files-button"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["session-detail-view"].firstMatch.exists)
    }

    func testSessionScenarioTerminalScreenshotIsNotBlank() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        XCTAssertTrue(app.buttons["session-files-button"].firstMatch.waitForExistence(timeout: 3))
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
            additionalEnvironment: [
                "GLASSDECK_UI_TEST_TERMINAL_COLOR_SCHEME": "Default Light"
            ]
        )

        XCTAssertTrue(app.buttons["session-files-button"].firstMatch.waitForExistence(timeout: 3))
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
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.otherElements["remote-trackpad-view"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testRemoteScenarioDoesNotOfferLocalTerminalOverride() {
        let app = launchApp(scenario: "remote", openActiveSession: true)

        let menuButton = app.buttons["session-menu-button"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()

        XCTAssertFalse(app.buttons["View Local Terminal"].firstMatch.exists)
    }

    func testSessionScenarioCanToggleTerminalKeyboardFromTap() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: 5))
        waitForTerminalKeyboardState(presented: false, in: app)

        terminalSurface.tap()
        waitForTerminalKeyboardState(presented: true, in: app)

        terminalSurface.tap()
        waitForTerminalKeyboardState(presented: false, in: app)
    }

    func testSSHKeysSheetShowsEmptyStateWhenNoKeysExist() {
        let app = launchApp(scenario: "connections")

        app.buttons["connections-toolbar-menu"].firstMatch.tap()
        app.buttons["connections-menu-ssh-keys"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["SSH Keys"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Stored Keys"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Stored Keys"].firstMatch.exists)
    }

    func testTerminalSettingsExposeIndependentIPhoneAndExternalMonitorProfiles() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        let menuButton = app.buttons["session-menu-button"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()
        app.buttons["Settings"].firstMatch.tap()

        let targetPicker = app.segmentedControls["terminal-settings-target-picker"].firstMatch
        XCTAssertTrue(targetPicker.waitForExistence(timeout: 5))

        let profileSummary = app.otherElements["terminal-settings-profile-summary"].firstMatch
        XCTAssertTrue(profileSummary.waitForExistence(timeout: 5))
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
        XCTAssertTrue(sessionsTab.waitForExistence(timeout: 10))
        sessionsTab.tap()
        let animationSessionCard = app.descendants(matching: .any)
            .matching(identifier: "session-card-55555555-5555-5555-5555-555555555555")
            .firstMatch
        XCTAssertTrue(animationSessionCard.waitForExistence(timeout: 10))

        app.tabBars.buttons["Connections"].firstMatch.tap()

        let connectionRow = app.buttons[
            connectionRowIdentifier(name: "Glassdeck Test SSH", host: "glassdeck-test.local")
        ].firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 10))
        assertScreenHasAverageBrightness(
            named: "connections-after-animation-switch",
            minimumAverageBrightness: 120
        )
    }

    func testFilesSheetCanLaunchFromSessionDetailScenario() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        XCTAssertTrue(app.buttons["session-files-button"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["session-files-button"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["sftp-browser-view"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Connect"].firstMatch.exists || app.staticTexts["Current Path"].firstMatch.exists)
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
        app.launchEnvironment.merge(additionalEnvironment) { _, new in new }
        app.launch()
        return app
    }
}
