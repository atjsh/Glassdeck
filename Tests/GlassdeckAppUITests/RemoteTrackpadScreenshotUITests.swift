import XCTest

@MainActor
final class RemoteTrackpadScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRemoteTrackpadPreviewCapturesModeAndKeyboardScreenshots() throws {
        try requireScreenshotCaptureEnabled()

        let app = launchUITestApp(
            scenario: "remote",
            openActiveSession: true
        )

        let remoteTrackpad = app.otherElements["remote-trackpad-view"].firstMatch
        XCTAssertTrue(remoteTrackpad.waitForExistence(timeout: 5))
        captureScreenshot(named: "docker-remote-trackpad-cursor")

        let modePicker = app.segmentedControls["remote-mode-picker"].firstMatch
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        modePicker.buttons["Mouse"].firstMatch.tap()
        captureScreenshot(named: "docker-remote-trackpad-mouse")

        let keyboardToggle = app.buttons["remote-keyboard-toggle"].firstMatch
        XCTAssertTrue(keyboardToggle.waitForExistence(timeout: 5))
        keyboardToggle.tap()
        captureScreenshot(named: "docker-remote-trackpad-keyboard")
    }
}
