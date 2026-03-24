import XCTest
@testable import GlassdeckBuildCore

final class TestCommandTests: XCTestCase {
    func testOutputModeDefaultsToFiltered() throws {
        let command = try TestCommand.parse([])
        XCTAssertEqual(command.xcodeOutputMode, .filtered)
    }

    func testOutputModeCanBeSetToQuiet() throws {
        let command = try TestCommand.parse(["--xcode-output-mode", "quiet"])
        XCTAssertEqual(command.xcodeOutputMode, .quiet)
    }

    func testResolvedActionRejectsMutuallyExclusiveModes() throws {
        let command = try TestCommand.parse(["--build-for-testing", "--test-without-building"])

        XCTAssertThrowsError(try command.resolvedAction())
    }

    func testExecutionRequestAddsOnlyTestingArgumentsInOrder() throws {
        let command = try TestCommand.parse(
            [
                "--scheme", "unit",
                "--only-testing", "GlassdeckAppTests/One.test",
                "--only-testing", "GlassdeckAppTests/Two.test",
            ]
        )

        let request = try command.executionRequest(simulatorIdentifier: "SIM-1234")

        XCTAssertEqual(request.action, .test)
        XCTAssertEqual(request.scheme, .unit)
        XCTAssertEqual(
            request.additionalArguments,
            [
                "-only-testing", "GlassdeckAppTests/One.test",
                "-only-testing", "GlassdeckAppTests/Two.test",
            ]
        )
    }

    func testResolvedExecutionRequestUsesResolvedSimulatorIdentifier() async throws {
        let fixtureOutput = """
            == Devices ==
              iPhone Air (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)
        """
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: fixtureOutput))
            ]
        )
        let command = try TestCommand.parse(["--simulator", "iPhone Air"])

        let request = try await command.resolvedExecutionRequest(using: runner)

        XCTAssertEqual(request.simulatorIdentifier, "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    }

    func testPreviewInvocationUsesTestArtifactRoots() throws {
        let command = try TestCommand.parse(["--scheme", "ui", "--test-without-building"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 3,
            processRunner: ScriptedProcessRunner(responses: [])
        )
        let request = try command.executionRequest(simulatorIdentifier: "SIM-1234")

        let invocation = try command.previewInvocation(using: context, request: request)
        let renderedArguments = invocation.arguments.joined(separator: " ")

        XCTAssertTrue(invocation.arguments.contains("test-without-building"))
        XCTAssertTrue(invocation.arguments.contains("platform=iOS Simulator,id=SIM-1234"))
        XCTAssertTrue(invocation.arguments.contains("GlassdeckAppUI"))
        XCTAssertTrue(renderedArguments.contains("/tmp/ws/Glassdeck/.build/glassdeck-build/results/test/"))
        XCTAssertEqual(invocation.outputMode, ProcessOutputMode.captureAndStreamTimestampedFiltered(.xcodebuild))
    }

    func testPreviewInvocationUsesQuietOutputModeWhenRequested() throws {
        let command = try TestCommand.parse(["--xcode-output-mode", "quiet"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 3,
            processRunner: ScriptedProcessRunner(responses: [])
        )

        let invocation = try command.previewInvocation(using: context)

        XCTAssertEqual(invocation.outputMode, .captureOnly)
    }
}
