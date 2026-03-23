import Foundation
import XCTest
@testable import GlassdeckBuildCore

final class LiveSSHFixtureTests: XCTestCase {
    func testStartBuildsRuntimeEnvironment() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "ssh-container\n")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "healthy\n")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "interface: en0\n")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "192.168.1.5\n")),
            ]
        )
        let controller = DockerComposeController(
            processRunner: runner,
            configuration: DockerComposeConfiguration(
                projectName: "glassdeck-test-ssh",
                composeFile: URL(fileURLWithPath: "/workspace/Scripts/docker/ssh-compose.yml")
            )
        )
        let resolver = HostIPResolver(processRunner: runner)
        let fixture = LiveSSHFixture(
            docker: controller,
            hostResolver: resolver,
            configuration: LiveSSHFixtureConfiguration(
                dockerHostPort: 22222,
                username: "glassdeck",
                password: "glassdeck",
                privateKeyPath: "/tmp/key"
            )
        )

        let env = try await fixture.start()

        XCTAssertEqual(env.host, "192.168.1.5")
        XCTAssertEqual(env.port, 22222)
        XCTAssertEqual(runner.calls.count, 5)
    }

    func testStopInvokesComposeDown() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: ""))
            ]
        )
        let controller = DockerComposeController(
            processRunner: runner,
            configuration: DockerComposeConfiguration(
                projectName: "glassdeck-test-ssh",
                composeFile: URL(fileURLWithPath: "/workspace/Scripts/docker/ssh-compose.yml")
            )
        )
        let resolver = HostIPResolver(processRunner: runner)
        let fixture = LiveSSHFixture(
            docker: controller,
            hostResolver: resolver,
            configuration: LiveSSHFixtureConfiguration(
                dockerHostPort: 22222,
                username: "glassdeck",
                password: "glassdeck",
                privateKeyPath: "/tmp/key"
            )
        )

        try await fixture.stop()
        XCTAssertEqual(runner.calls.last?.arguments.suffix(2), ["down", "--remove-orphans"])
    }
}
