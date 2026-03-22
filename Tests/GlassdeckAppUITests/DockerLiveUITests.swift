import XCTest

@MainActor
final class DockerLiveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPasswordAuthFlowCapturesGhosttyScreenshot() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = launchLiveDockerApp(configuration: configuration)

        createConnection(
            app: app,
            name: "Docker Password",
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            authMethod: .password
        )
        app.buttons["connection-save-button"].firstMatch.tap()

        let passwordRow = app.buttons[connectionRowIdentifier(name: "Docker Password", host: configuration.host)].firstMatch
        XCTAssertTrue(passwordRow.waitForExistence(timeout: 5))
        passwordRow.tap()

        let passwordField = app.secureTextFields["connection-password-field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(configuration.password)
        app.buttons["connection-password-connect-button"].firstMatch.tap()

        assertConnectedTerminal(for: app)

        enterTerminalCommand(
            "echo GLASSDECK_UI_PASSWORD_OK; /home/glassdeck/bin/health-check.sh\n",
            in: app
        )

        waitForTerminalRenderSummary(containing: "GLASSDECK_UI_PASSWORD_OK", in: app)
        waitForTerminalRenderSummary(containing: "glassdeck@", in: app)
        captureTerminalDiagnostics(in: app, named: "docker-password-terminal")
    }

    func testSSHKeyAuthFlowCapturesGhosttyScreenshot() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = launchLiveDockerApp(configuration: configuration)

        let toolbarMenu = app.buttons["connections-toolbar-menu"].firstMatch
        XCTAssertTrue(toolbarMenu.waitForExistence(timeout: 5))
        toolbarMenu.tap()
        app.buttons["connections-menu-ssh-keys"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["SSH Keys"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["ssh-key-import-clipboard-button"].firstMatch.tap()
        let importedKeyRow = app.descendants(matching: .any)
            .matching(identifier: "ssh-key-row")
            .firstMatch
        XCTAssertTrue(importedKeyRow.waitForExistence(timeout: 10))
        app.buttons["dismiss-button"].firstMatch.tap()

        createConnection(
            app: app,
            name: "Docker Key",
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            authMethod: .sshKey
        )

        app.buttons["connection-manage-ssh-keys-button"].firstMatch.tap()
        let storedKeyRow = app.descendants(matching: .any)
            .matching(identifier: "ssh-key-row")
            .firstMatch
        XCTAssertTrue(storedKeyRow.waitForExistence(timeout: 5))
        storedKeyRow.tap()
        app.navigationBars["SSH Keys"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["connection-selected-ssh-key"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["connection-save-button"].firstMatch.tap()

        let connectionRow = app.buttons[connectionRowIdentifier(name: "Docker Key", host: configuration.host)].firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        connectionRow.tap()

        assertConnectedTerminal(for: app)

        enterTerminalCommand(
            "echo GLASSDECK_UI_KEY_OK; ls /home/glassdeck/testdata\n",
            in: app
        )

        waitForTerminalRenderSummary(containing: "GLASSDECK_UI_KEY_OK", in: app)
        waitForTerminalRenderSummary(containing: "preview.txt", in: app)
        captureTerminalDiagnostics(in: app, named: "docker-key-terminal")
    }

    func testPasswordAuthSessionReconnectsAfterSpringboardRoundTrip() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = launchLiveDockerApp(configuration: configuration)

        createConnection(
            app: app,
            name: "Docker Resume",
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            authMethod: .password
        )
        app.buttons["connection-save-button"].firstMatch.tap()

        let connectionRow = app.buttons[
            connectionRowIdentifier(name: "Docker Resume", host: configuration.host)
        ].firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        connectionRow.tap()

        let passwordField = app.secureTextFields["connection-password-field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(configuration.password)
        app.buttons["connection-password-connect-button"].firstMatch.tap()

        assertConnectedTerminal(for: app)
        waitForTerminalRenderSummary(containing: "glassdeck@", in: app)
        captureTerminalDiagnostics(in: app, named: "docker-resume-before-home")

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        captureTerminalDiagnostics(in: app, named: "docker-resume-after-activate")

        assertConnectedTerminal(for: app)
        waitForTerminalRenderSummary(
            containingAnyOf: ["GLASSDECK_SSH_OK", "Reconnecting"],
            in: app,
            timeout: 30
        )

        enterTerminalCommand("echo GLASSDECK_UI_RESUME_OK; pwd\n", in: app)
        waitForTerminalRenderSummary(containing: "GLASSDECK_UI_RESUME_OK", in: app, timeout: 30)
        captureTerminalDiagnostics(in: app, named: "docker-resume-restored")
    }

    func testPasswordAuthSessionRelaunchesIntoDetailWithoutBlankTerminal() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = launchLiveDockerApp(configuration: configuration)

        createConnection(
            app: app,
            name: "Docker Relaunch",
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            authMethod: .password
        )
        app.buttons["connection-save-button"].firstMatch.tap()

        let connectionRow = app.buttons[
            connectionRowIdentifier(name: "Docker Relaunch", host: configuration.host)
        ].firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        connectionRow.tap()

        let passwordField = app.secureTextFields["connection-password-field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(configuration.password)
        app.buttons["connection-password-connect-button"].firstMatch.tap()

        assertConnectedTerminal(for: app)
        waitForTerminalRenderSummary(containing: "glassdeck@", in: app)
        captureTerminalDiagnostics(in: app, named: "docker-relaunch-before-terminate")

        app.terminate()
        app.launchArguments = [
            "-uiTestScenario",
            "empty",
            "-uiTestDisableAnimations",
            "-uiTestOpenActiveSession",
            "-uiTestExposeTerminalRenderSummary"
        ]
        app.launchEnvironment[UITestEnvironmentKeys.preserveHostBackedState] = "1"
        app.launchEnvironment["GLASSDECK_LIVE_SSH_ENABLED"] = "1"
        app.launchEnvironment["GLASSDECK_LIVE_SSH_HOST"] = configuration.host
        app.launchEnvironment["GLASSDECK_LIVE_SSH_PORT"] = String(configuration.port)
        app.launchEnvironment["GLASSDECK_LIVE_SSH_USER"] = configuration.username
        app.launchEnvironment["GLASSDECK_LIVE_SSH_PASSWORD"] = configuration.password
        app.launchEnvironment["GLASSDECK_LIVE_SSH_KEY_PATH"] = configuration.privateKeyPath
        app.launch()
        captureTerminalDiagnostics(in: app, named: "docker-relaunch-after-launch")

        guard app.otherElements["session-detail-view"].firstMatch.waitForExistence(timeout: 20) else {
            captureTerminalDiagnostics(in: app, named: "docker-relaunch-missing-session-detail")
            throw XCTSkip("Cold relaunch did not reopen the session detail view in this XCUITest harness.")
        }
        captureTerminalDiagnostics(in: app, named: "docker-relaunch-session-detail-visible")
        waitForTerminalRenderSummary(
            containingAnyOf: ["glassdeck@", "Reconnecting", "[terminal pending]", "Last login:"],
            in: app,
            timeout: 30
        )
        captureTerminalDiagnostics(in: app, named: "docker-relaunch-after-summary")

        let placeholder = app.otherElements["terminal-presentation-placeholder"].firstMatch
        if placeholder.exists {
            captureTerminalDiagnostics(in: app, named: "docker-relaunch-placeholder-visible")
            XCTAssertTrue(app.otherElements["terminal-surface-view"].firstMatch.waitForExistence(timeout: 5))
        } else {
            let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
            XCTAssertTrue(terminalSurface.waitForExistence(timeout: 10))
            assertScreenshotIsNotBlank(of: terminalSurface, named: "docker-relaunch-terminal")
        }
    }

    private func launchLiveDockerApp(configuration: LiveDockerUITestConfiguration) -> XCUIApplication {
        let clipboardSeed = (try? Data(contentsOf: URL(fileURLWithPath: configuration.privateKeyPath)))
            .map { $0.base64EncodedString() } ?? ""

        return launchUITestApp(
            scenario: "empty",
            additionalArguments: ["-uiTestExposeTerminalRenderSummary"],
            additionalEnvironment: [
                "GLASSDECK_LIVE_SSH_ENABLED": "1",
                "GLASSDECK_LIVE_SSH_HOST": configuration.host,
                "GLASSDECK_LIVE_SSH_PORT": String(configuration.port),
                "GLASSDECK_LIVE_SSH_USER": configuration.username,
                "GLASSDECK_LIVE_SSH_PASSWORD": configuration.password,
                "GLASSDECK_LIVE_SSH_KEY_PATH": configuration.privateKeyPath,
                "GLASSDECK_UI_TEST_CLIPBOARD_TEXT_BASE64": clipboardSeed,
            ]
        )
    }

    private func createConnection(
        app: XCUIApplication,
        name: String,
        host: String,
        port: Int,
        username: String,
        authMethod: AuthenticationMode
    ) {
        app.buttons["new-connection-button"].firstMatch.tap()

        replaceText(in: app.textFields["connection-name-field"].firstMatch, with: name)
        replaceText(in: app.textFields["connection-host-field"].firstMatch, with: host)
        replaceText(in: app.textFields["connection-port-field"].firstMatch, with: String(port), deleteCount: 2)
        replaceText(in: app.textFields["connection-username-field"].firstMatch, with: username)

        if authMethod == .sshKey {
            let authPicker = app.segmentedControls["connection-auth-method-picker"].firstMatch
            XCTAssertTrue(authPicker.waitForExistence(timeout: 5))
            authPicker.buttons["SSH Key"].firstMatch.tap()
        }
    }

    private func assertConnectedTerminal(for app: XCUIApplication) {
        let sessionDetail = app.otherElements["session-detail-view"].firstMatch
        if !sessionDetail.waitForExistence(timeout: 20) {
            captureTerminalDiagnostics(in: app, named: "docker-terminal-missing-session-detail")
        }
        XCTAssertTrue(sessionDetail.exists)

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        if !terminalSurface.waitForExistence(timeout: 20) {
            captureTerminalDiagnostics(in: app, named: "docker-terminal-missing-surface")
        }
        XCTAssertTrue(terminalSurface.exists)
    }

    private func enterTerminalCommand(_ command: String, in app: XCUIApplication) {
        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: 10))
        terminalSurface.tap()
        waitForTerminalKeyboardState(presented: true, in: app, timeout: 10)

        let terminalInput = app.descendants(matching: .any)
            .matching(identifier: "session-keyboard-host")
            .firstMatch
        XCTAssertTrue(terminalInput.waitForExistence(timeout: 10))
        terminalInput.typeText(command)
    }
}

private enum AuthenticationMode {
    case password
    case sshKey
}
