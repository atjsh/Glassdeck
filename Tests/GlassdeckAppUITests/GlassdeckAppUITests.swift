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

    func testSessionScenarioCanLaunchIntoDetail() {
        let app = launchApp(scenario: "sessions", openActiveSession: true)

        XCTAssertTrue(app.buttons["session-files-button"].firstMatch.waitForExistence(timeout: 3))
        waitForTerminalRenderSummary(
            containingAnyOf: ["GLASSDECK_SSH_OK", "preview.txt", "/home/glassdeck"],
            in: app
        )
    }

    func testRemoteScenarioAutoEntersTrackpadView() {
        let app = launchApp(scenario: "remote", openActiveSession: true)

        XCTAssertTrue(app.otherElements["remote-trackpad-view"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testRemoteScenarioCanLaunchIntoLocalTerminalOverride() {
        let app = launchApp(
            scenario: "remote",
            openActiveSession: true,
            additionalArguments: ["-uiTestForceLocalTerminal"]
        )

        XCTAssertTrue(app.buttons["session-files-button"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["terminal-surface-view"].firstMatch.waitForExistence(timeout: 3))
        waitForTerminalRenderSummary(
            containingAnyOf: ["GLASSDECK_SSH_OK", "preview.txt", "/home/glassdeck"],
            in: app
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
        additionalArguments: [String] = []
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
        app.launch()
        return app
    }
}
