import XCTest
@testable import GlassdeckBuildCore

final class BuildCommandTests: XCTestCase {
    func testOutputModeDefaultsToFiltered() throws {
        let command = try BuildCommand.parse([])
        XCTAssertEqual(command.xcodeOutputMode, .filtered)
    }

    func testOutputModeCanBeSetToFull() throws {
        let command = try BuildCommand.parse(["--xcode-output-mode", "full"])
        XCTAssertEqual(command.xcodeOutputMode, .full)
    }

    func testExecutionRequestUsesBuildForTestingWhenEnabled() throws {
        let command = try BuildCommand.parse(["--scheme", "ui", "--build-for-testing"])

        let request = command.executionRequest(simulatorIdentifier: "SIM-1234")

        XCTAssertEqual(request.action, .buildForTesting)
        XCTAssertEqual(request.scheme, .ui)
    }

    func testResolvedExecutionRequestUsesResolvedSimulatorIdentifier() async throws {
        let fixtureOutput = """
            == Devices ==
              iPhone 17 Pro (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)
        """
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: fixtureOutput))
            ]
        )
        let command = try BuildCommand.parse(["--simulator", "iPhone 17 Pro"])

        let request = try await command.resolvedExecutionRequest(using: runner)

        XCTAssertEqual(request.simulatorIdentifier, "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    }

    func testPreviewInvocationUsesSharedContextPaths() throws {
        let command = try BuildCommand.parse(["--scheme", "app"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 2,
            processRunner: ScriptedProcessRunner(responses: [])
        )
        let request = command.executionRequest(simulatorIdentifier: "SIM-1234")

        let invocation = command.previewInvocation(using: context, request: request)
        let renderedArguments = invocation.arguments.joined(separator: " ")

        XCTAssertEqual(invocation.executable, "/usr/bin/xcodebuild")
        XCTAssertEqual(invocation.outputMode, ProcessOutputMode.captureAndStreamTimestampedFiltered(.xcodebuild))
        XCTAssertTrue(invocation.arguments.contains("build"))
        XCTAssertTrue(renderedArguments.contains("/tmp/ws/Glassdeck/.build/glassdeck-build/results/build/"))
        XCTAssertTrue(invocation.arguments.contains("platform=iOS Simulator,id=SIM-1234"))
        XCTAssertTrue(invocation.arguments.contains("GlassdeckApp"))
    }

    func testPreviewInvocationUsesFullOutputModeWhenRequested() throws {
        let command = try BuildCommand.parse(["--xcode-output-mode", "full"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 2,
            processRunner: ScriptedProcessRunner(responses: [])
        )

        let invocation = command.previewInvocation(using: context)

        XCTAssertEqual(invocation.outputMode, .captureAndStreamTimestamped)
    }
}
