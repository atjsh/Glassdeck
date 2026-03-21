import XCTest

struct LiveDockerUITestConfiguration {
    let host: String
    let port: Int
    let username: String
    let password: String
    let privateKeyPath: String

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard environment["GLASSDECK_LIVE_SSH_ENABLED"] == "1" else {
            throw XCTSkip("Set GLASSDECK_LIVE_SSH_ENABLED=1 to run the live Docker UI tests.")
        }

        guard
            let host = environment["GLASSDECK_LIVE_SSH_HOST"],
            let portString = environment["GLASSDECK_LIVE_SSH_PORT"],
            let port = Int(portString),
            let username = environment["GLASSDECK_LIVE_SSH_USER"],
            let password = environment["GLASSDECK_LIVE_SSH_PASSWORD"],
            let privateKeyPath = environment["GLASSDECK_LIVE_SSH_KEY_PATH"]
        else {
            throw XCTSkip("Live Docker UI test environment variables are incomplete.")
        }

        return Self(
            host: host,
            port: port,
            username: username,
            password: password,
            privateKeyPath: privateKeyPath
        )
    }
}

extension XCTestCase {
    @discardableResult
    func launchUITestApp(
        scenario: String,
        openActiveSession: Bool = false,
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", scenario, "-uiTestDisableAnimations"]
        if openActiveSession {
            app.launchArguments.append("-uiTestOpenActiveSession")
        }
        app.launchArguments.append(contentsOf: additionalArguments)
        app.launchEnvironment.merge(additionalEnvironment) { _, new in new }
        app.launch()
        return app
    }

    func captureScreenshot(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func waitForTerminalRenderSummary(
        containing marker: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let summaryElement = app.descendants(matching: .any)
            .matching(identifier: "terminal-render-summary")
            .firstMatch
        XCTAssertTrue(
            summaryElement.waitForExistence(timeout: 10),
            "Expected the terminal render summary accessibility element to exist.",
            file: file,
            line: line
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let summary = (summaryElement.value as? String) ?? summaryElement.label
            if summary.contains(marker) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let currentSummary = (summaryElement.value as? String) ?? summaryElement.label
        XCTFail(
            "Timed out waiting for terminal render summary to contain '\(marker)'. Current summary: \(currentSummary)",
            file: file,
            line: line
        )
    }

    func waitForTerminalRenderSummary(
        containingAnyOf markers: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(markers.isEmpty, "Expected at least one terminal marker to wait for.", file: file, line: line)

        let summaryElement = app.descendants(matching: .any)
            .matching(identifier: "terminal-render-summary")
            .firstMatch
        XCTAssertTrue(
            summaryElement.waitForExistence(timeout: 10),
            "Expected the terminal render summary accessibility element to exist.",
            file: file,
            line: line
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let summary = (summaryElement.value as? String) ?? summaryElement.label
            if markers.contains(where: summary.contains) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let currentSummary = (summaryElement.value as? String) ?? summaryElement.label
        XCTFail(
            "Timed out waiting for terminal render summary to contain any of: \(markers). Current summary: \(currentSummary)",
            file: file,
            line: line
        )
    }

    func replaceText(
        in element: XCUIElement,
        with text: String,
        deleteCount: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected input element to exist.", file: file, line: line)
        element.tap()
        if deleteCount > 0 {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deleteCount))
        }
        element.typeText(text)
    }

    func connectionRowIdentifier(name: String, host: String) -> String {
        "connection-row-\(accessibilitySlug(name))-\(accessibilitySlug(host))"
    }

    func requireScreenshotCaptureEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard environment["GLASSDECK_UI_SCREENSHOT_CAPTURE"] == "1" else {
            throw XCTSkip("Set GLASSDECK_UI_SCREENSHOT_CAPTURE=1 to run screenshot-only UI tests.")
        }
    }

    private func accessibilitySlug(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
