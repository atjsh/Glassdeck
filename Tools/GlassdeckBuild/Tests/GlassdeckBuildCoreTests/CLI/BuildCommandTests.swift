import XCTest
@testable import GlassdeckBuildCore

final class BuildCommandTests: XCTestCase {
    func testExecutionRequestUsesBuildForTestingWhenEnabled() throws {
        let command = try BuildCommand.parse(["--scheme", "ui", "--build-for-testing"])

        let request = command.executionRequest()

        XCTAssertEqual(request.action, .buildForTesting)
        XCTAssertEqual(request.scheme, .ui)
    }

    func testPreviewInvocationUsesSharedContextPaths() throws {
        let command = try BuildCommand.parse(["--scheme", "app"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 2,
            processRunner: ScriptedProcessRunner(responses: [])
        )

        let invocation = command.previewInvocation(using: context)
        let renderedArguments = invocation.arguments.joined(separator: " ")

        XCTAssertEqual(invocation.executable, "/usr/bin/xcodebuild")
        XCTAssertTrue(invocation.arguments.contains("build"))
        XCTAssertTrue(renderedArguments.contains("/tmp/ws/Glassdeck/.build/glassdeck-build/results/build/"))
        XCTAssertTrue(invocation.arguments.contains("platform=iOS Simulator,name=iPhone 17"))
        XCTAssertTrue(invocation.arguments.contains("GlassdeckApp"))
    }
}
