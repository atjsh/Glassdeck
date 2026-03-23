import Foundation
import XCTest
@testable import GlassdeckBuildCore

final class XcodeCommandExecutorTests: XCTestCase {
    func testPreviewInvocationUsesContextPathsAndConfiguredOutputMode() {
        let workspace = WorkspaceContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws"),
            projectRootName: "Glassdeck"
        )
        let runner = ScriptedProcessRunner(responses: [])
        let context = CommandSupport.executionContext(
            workspace: workspace,
            simulatorName: "iPhone 17",
            workerID: 4,
            processRunner: runner
        )
        let executor = XcodeCommandExecutor(
            context: context,
            outputMode: .captureAndStreamTimestamped
        )

        let invocation = executor.previewInvocation(
            for: XcodeCommandRequest(action: .test, scheme: .ui)
        )
        let renderedArguments = invocation.arguments.joined(separator: " ")

        XCTAssertEqual(invocation.executable, "/usr/bin/xcodebuild")
        XCTAssertEqual(invocation.outputMode, .captureAndStreamTimestamped)
        XCTAssertTrue(renderedArguments.contains("/tmp/ws/Glassdeck/.build/glassdeck-build/results/test/"))
    }

    func testExecuteUsesConfiguredOutputMode() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-command-executor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
            ]
        )
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: tempRoot, projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 1,
            processRunner: runner
        )
        let executor = XcodeCommandExecutor(
            context: context,
            outputMode: .captureAndStreamTimestamped
        )

        _ = try await executor.execute(
            XcodeCommandRequest(action: .build, scheme: .app)
        )

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.outputMode, .captureAndStreamTimestamped)
    }
}
