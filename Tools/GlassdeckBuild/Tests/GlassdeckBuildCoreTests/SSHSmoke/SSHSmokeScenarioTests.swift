import XCTest
@testable import GlassdeckBuildCore

final class SSHSmokeScenarioTests: XCTestCase {
    func testPasswordScenarioUsesExpectedDefaultMarker() {
        let scenario = SSHSmokeScenario.password(
            host: "127.0.0.1",
            port: 2222,
            username: "glassdeck",
            password: "secret"
        )

        XCTAssertEqual(scenario.expectedSubstring, "GLASSDECK_SSH_SMOKE_OK")
        XCTAssertEqual(scenario.authentication.label, "password")
    }

    func testPrivateKeyScenarioKeepsConfiguredPath() {
        let scenario = SSHSmokeScenario.privateKey(
            host: "127.0.0.1",
            port: 2222,
            username: "glassdeck",
            privateKeyPath: "/tmp/key"
        )

        if case let .privateKey(path) = scenario.authentication {
            XCTAssertEqual(path, "/tmp/key")
        } else {
            XCTFail("Expected private-key authentication")
        }
    }
}
