import XCTest
@testable import GlassdeckBuildCore

final class TestCommandTests: XCTestCase {
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

        let request = try command.executionRequest()

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

    func testPreviewInvocationUsesTestArtifactRoots() throws {
        let command = try TestCommand.parse(["--scheme", "ui", "--test-without-building"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 3,
            processRunner: ScriptedProcessRunner(responses: [])
        )

        let invocation = try command.previewInvocation(using: context)
        let renderedArguments = invocation.arguments.joined(separator: " ")

        XCTAssertTrue(invocation.arguments.contains("test-without-building"))
        XCTAssertTrue(invocation.arguments.contains("GlassdeckAppUI"))
        XCTAssertTrue(renderedArguments.contains("/tmp/ws/Glassdeck/.build/glassdeck-build/results/test/"))
    }
}
