import XCTest
@testable import GlassdeckBuildCore

final class SimulatorEnvironmentTests: XCTestCase {
    func testLaunchctlAssignmentsExposeExpectedKeys() {
        let environment = SimulatorEnvironment(
            host: "127.0.0.1",
            port: 22222,
            username: "glassdeck",
            password: "password",
            keyPath: "/tmp/key",
            screenshotCapture: true
        )

        let assignments = environment.launchctlAssignments
        XCTAssertEqual(assignments["GLASSDECK_LIVE_SSH_HOST"], "127.0.0.1")
        XCTAssertEqual(assignments["GLASSDECK_LIVE_SSH_PORT"], "22222")
        XCTAssertEqual(assignments["GLASSDECK_LIVE_SSH_USER"], "glassdeck")
        XCTAssertEqual(assignments["GLASSDECK_LIVE_SSH_PASSWORD"], "password")
        XCTAssertEqual(assignments["GLASSDECK_LIVE_SSH_KEY_PATH"], "/tmp/key")
        XCTAssertEqual(assignments["GLASSDECK_UI_SCREENSHOT_CAPTURE"], "1")
    }

    func testLaunchctlCommandsContainBothSetenvAndUnsetenv() {
        let environment = SimulatorEnvironment(
            host: "127.0.0.1",
            port: 22222,
            username: "glassdeck",
            password: "password",
            keyPath: "/tmp/key"
        )
        let setenv = environment.launchctlSetenvInvocations(simulatorIdentifier: "SIM123")
        let unsetenv = environment.launchctlUnsetenvInvocations(simulatorIdentifier: "SIM123")

        XCTAssertEqual(setenv.count, 6)
        XCTAssertEqual(unsetenv.count, 6)
        XCTAssertEqual(setenv.first?.arguments, ["xcrun", "simctl", "spawn", "SIM123", "launchctl", "setenv", "GLASSDECK_LIVE_SSH_ENABLED", "1"])
        XCTAssertEqual(unsetenv.last?.arguments, ["xcrun", "simctl", "spawn", "SIM123", "launchctl", "unsetenv", "GLASSDECK_LIVE_SSH_KEY_PATH"])
    }

    func testXcodeBuildArgumentPairsAreDeterministic() {
        let environment = SimulatorEnvironment(
            host: "127.0.0.1",
            port: 22,
            username: "u",
            password: "p",
            keyPath: "/tmp/key",
            screenshotCapture: false
        )

        let args = environment.xcodeBuildArgumentList()
        XCTAssertEqual(args.count, 12)
        XCTAssertTrue(args.contains("GLASSDECK_LIVE_SSH_ENABLED=1"))
        XCTAssertTrue(args.contains("SIMCTL_CHILD_GLASSDECK_LIVE_SSH_KEY_PATH=/tmp/key"))
        XCTAssertFalse(args.contains("GLASSDECK_UI_SCREENSHOT_CAPTURE=1"))
        XCTAssertFalse(args.contains("SIMCTL_CHILD_GLASSDECK_UI_SCREENSHOT_CAPTURE=1"))
    }

    func testXcodeBuildPairsIncludeScreenshotWhenEnabled() {
        let environment = SimulatorEnvironment(
            host: "127.0.0.1",
            port: 22,
            username: "u",
            password: "p",
            keyPath: "/tmp/key",
            screenshotCapture: true
        )

        let assignments = environment.xcodeBuildAssignments
        XCTAssertEqual(assignments["SIMCTL_CHILD_GLASSDECK_UI_SCREENSHOT_CAPTURE"], "1")
        XCTAssertEqual(assignments["GLASSDECK_UI_SCREENSHOT_CAPTURE"], "1")
    }
}
