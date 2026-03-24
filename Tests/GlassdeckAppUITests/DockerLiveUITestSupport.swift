import XCTest

enum LiveDockerUITestSetupError: Error, LocalizedError {
    case missingKeyMaterial(String)
    case unreadableKeyMaterial(String)

    var errorDescription: String? {
        switch self {
        case .missingKeyMaterial(let path):
            "Live Docker UI test key material is missing at \(path)."
        case .unreadableKeyMaterial(let path):
            "Live Docker UI test key material is unreadable at \(path)."
        }
    }
}

@MainActor
extension XCTestCase {
    func launchLiveDockerApp(configuration: LiveDockerUITestConfiguration) throws -> XCUIApplication {
        let clipboardSeed = try liveDockerClipboardSeed(from: configuration)
        var environment = liveDockerLaunchEnvironment(from: configuration)
        environment["GLASSDECK_UI_TEST_CLIPBOARD_TEXT_BASE64"] = clipboardSeed

        return launchUITestApp(
            scenario: "empty",
            additionalArguments: ["-uiTestExposeTerminalRenderSummary"],
            additionalEnvironment: environment
        )
    }

    func launchLiveDockerHostBackedApp(configuration: LiveDockerUITestConfiguration) -> XCUIApplication {
        launchHostBackedUITestApp(
            openActiveSession: true,
            additionalArguments: ["-uiTestExposeTerminalRenderSummary"],
            additionalEnvironment: liveDockerLaunchEnvironment(from: configuration)
        )
    }

    func launchSeededLiveDockerSSHKeyApp(
        configuration: LiveDockerUITestConfiguration,
        connectionName: String,
        connectedCommand: String? = nil
    ) throws -> XCUIApplication {
        try launchSeededLiveDockerApp(
            configuration: configuration,
            connectionName: connectionName,
            connectedCommand: connectedCommand,
            preserveHostState: true,
            requirePreviewSurface: true
        )
    }

    func launchSeededLiveDockerProbeApp(
        configuration: LiveDockerUITestConfiguration,
        connectionName: String,
        requirePreviewSurface: Bool,
        connectedCommand: String? = nil
    ) throws -> XCUIApplication {
        try launchSeededLiveDockerApp(
            configuration: configuration,
            connectionName: connectionName,
            connectedCommand: connectedCommand,
            preserveHostState: false,
            requirePreviewSurface: requirePreviewSurface
        )
    }

    private func launchSeededLiveDockerApp(
        configuration: LiveDockerUITestConfiguration,
        connectionName: String,
        connectedCommand: String?,
        preserveHostState: Bool,
        requirePreviewSurface: Bool
    ) throws -> XCUIApplication {
        let clipboardSeed = try liveDockerClipboardSeed(from: configuration)
        var environment = liveDockerLaunchEnvironment(from: configuration)
        environment["GLASSDECK_UI_TEST_CLIPBOARD_TEXT_BASE64"] = clipboardSeed
        environment["GLASSDECK_UI_TEST_SEED_LIVE_SSH_SESSION"] = "1"
        environment["GLASSDECK_UI_TEST_SEED_LIVE_SSH_NAME"] = connectionName
        if let connectedCommand {
            environment["GLASSDECK_UI_TEST_CONNECTED_TERMINAL_COMMAND_BASE64"] =
                Data(connectedCommand.utf8).base64EncodedString()
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestDisableAnimations",
            "-uiTestOpenActiveSession",
            "-uiTestExposeTerminalRenderSummary",
        ]
        app.launchEnvironment.merge(uiTestFilesystemEnvironment()) { current, _ in current }
        if requirePreviewSurface {
            app.launchArguments.append("-uiTestRequirePreviewSurface")
        }
        if preserveHostState {
            app.launchEnvironment[UITestEnvironmentKeys.preserveHostBackedState] = "1"
        }
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        return app
    }

    func liveDockerLaunchEnvironment(from configuration: LiveDockerUITestConfiguration) -> [String: String] {
        [
            "GLASSDECK_LIVE_SSH_ENABLED": "1",
            "GLASSDECK_LIVE_SSH_HOST": configuration.host,
            "GLASSDECK_LIVE_SSH_PORT": String(configuration.port),
            "GLASSDECK_LIVE_SSH_USER": configuration.username,
            "GLASSDECK_LIVE_SSH_PASSWORD": configuration.password,
            "GLASSDECK_LIVE_SSH_KEY_PATH": configuration.privateKeyPath,
        ]
    }

    func assertConnectedTerminal(for app: XCUIApplication) {
        let sessionDetail = app.otherElements["session-detail-view"].firstMatch
        if !sessionDetail.waitForExistence(timeout: 20) {
            captureTerminalDiagnostics(in: app, named: "docker-terminal-missing-session-detail")
        }
        XCTAssertTrue(
            sessionDetail.exists,
            "Expected session detail to exist while app state was \(uiApplicationStateDescription(app.state))."
        )

        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        if !terminalSurface.waitForExistence(timeout: 20) {
            captureTerminalDiagnostics(in: app, named: "docker-terminal-missing-surface")
        }
        XCTAssertTrue(
            terminalSurface.exists,
            "Expected terminal surface to exist while app state was \(uiApplicationStateDescription(app.state))."
        )
    }

    func enterTerminalCommand(_ command: String, in app: XCUIApplication) {
        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: UITestTimeout.long))

        if currentTerminalKeyboardState(in: app) != "presented" {
            terminalSurface.tap()
        }

        let terminalInput = app.textFields["session-keyboard-host"].firstMatch
        XCTAssertTrue(terminalInput.waitForExistence(timeout: UITestTimeout.long))
        terminalInput.tap()
        terminalInput.typeText(command)
    }

    func liveDockerClipboardSeed(from configuration: LiveDockerUITestConfiguration) throws -> String {
        let keyURL = URL(fileURLWithPath: configuration.privateKeyPath)
        guard FileManager.default.fileExists(atPath: keyURL.path) else {
            throw LiveDockerUITestSetupError.missingKeyMaterial(keyURL.path)
        }

        do {
            return try Data(contentsOf: keyURL).base64EncodedString()
        } catch {
            throw LiveDockerUITestSetupError.unreadableKeyMaterial(keyURL.path)
        }
    }
}
