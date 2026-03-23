import Foundation
import XCTest
@testable import GlassdeckBuildCore

final class DockerComposeControllerTests: XCTestCase {
    func testInvocationCompositionForUpDownAndHealthChecks() {
        let runner = ScriptedProcessRunner(responses: [])
        let config = DockerComposeConfiguration(
            projectName: "glassdeck-test-ssh",
            composeFile: URL(fileURLWithPath: "/workspace/Scripts/docker/ssh-compose.yml"),
            runtimeDirectory: URL(fileURLWithPath: "/workspace/.build/docker-ssh")
        )
        let controller = DockerComposeController(processRunner: runner, configuration: config)

        XCTAssertEqual(
            controller.upInvocation().arguments,
            ["docker", "compose", "--project-name", "glassdeck-test-ssh", "-f", "/workspace/Scripts/docker/ssh-compose.yml", "up", "-d", "--build", "--remove-orphans"]
        )
        XCTAssertEqual(
            controller.downInvocation().arguments,
            ["docker", "compose", "--project-name", "glassdeck-test-ssh", "-f", "/workspace/Scripts/docker/ssh-compose.yml", "down", "--remove-orphans"]
        )
        XCTAssertEqual(
            controller.psInvocation().arguments,
            ["docker", "compose", "--project-name", "glassdeck-test-ssh", "-f", "/workspace/Scripts/docker/ssh-compose.yml", "ps", "-q", "ssh"]
        )
        XCTAssertEqual(
            controller.inspectHealthStringInvocation(containerID: "abc123").arguments,
            [
                "docker",
                "inspect",
                "--format",
                "{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}",
                "abc123",
            ]
        )
    }

    func testWaitForHealthyExitsWhenContainerHealthy() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "abc123\n")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "healthy\n")),
            ]
        )
        let config = DockerComposeConfiguration(
            projectName: "glassdeck",
            composeFile: URL(fileURLWithPath: "/workspace/Scripts/docker/ssh-compose.yml")
        )
        let controller = DockerComposeController(processRunner: runner, configuration: config)

        try await controller.waitForHealthy(maxAttempts: 5, pollDelayNanos: 1)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments[0], "docker")
        XCTAssertEqual(runner.calls[1].arguments[0], "docker")
    }

    func testContainerIdentifierReturnsNilWhenNoContainer() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "\n"))
            ]
        )
        let config = DockerComposeConfiguration(projectName: "glassdeck", composeFile: URL(fileURLWithPath: "/workspace/Scripts/docker/ssh-compose.yml"))
        let controller = DockerComposeController(processRunner: runner, configuration: config)
        let identifier = try await controller.containerIdentifier()
        XCTAssertNil(identifier)
    }
}
