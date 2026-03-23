import XCTest
@testable import GlassdeckBuildCore

final class LiveSSHEnvironmentTests: XCTestCase {
    func testAssignmentsIncludeBothLaunchctlAndSimctlChild() {
        let env = LiveSSHEnvironment(
            host: "10.0.0.2",
            port: 22222,
            username: "glassdeck",
            password: "secret",
            privateKeyPath: "/tmp/key",
            screenshotCapture: true
        )

        XCTAssertEqual(env.launchctlAssignments["GLASSDECK_LIVE_SSH_HOST"], "10.0.0.2")
        XCTAssertEqual(env.launchctlAssignments["GLASSDECK_LIVE_SSH_PORT"], "22222")
        XCTAssertEqual(env.xcodeBuildAssignments["SIMCTL_CHILD_GLASSDECK_LIVE_SSH_HOST"], "10.0.0.2")
        XCTAssertEqual(env.xcodeBuildAssignments["SIMCTL_CHILD_GLASSDECK_UI_SCREENSHOT_CAPTURE"], "1")
    }

    func testPairsRenderAsString() {
        let env = LiveSSHEnvironment(
            host: "10.0.0.2",
            port: 22222,
            username: "glassdeck",
            password: "secret",
            privateKeyPath: "/tmp/key",
            screenshotCapture: false
        )
        let pairs = env.asXcodeBuildPairs()

        XCTAssertTrue(pairs.contains("GLASSDECK_LIVE_SSH_ENABLED=1"))
        XCTAssertTrue(pairs.contains("SIMCTL_CHILD_GLASSDECK_LIVE_SSH_KEY_PATH=/tmp/key"))
    }
}
