import XCTest
@testable import GlassdeckBuildCore

final class CommandExecutionContextTests: XCTestCase {
    func testExecutionContextBuildsSharedRunnerState() {
        let workspace = WorkspaceContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws"),
            projectRootName: "Glassdeck"
        )
        let runner = ScriptedProcessRunner(responses: [])

        let context = CommandSupport.executionContext(
            workspace: workspace,
            simulatorName: "iPhone 17 Pro",
            workerID: 7,
            processRunner: runner
        )

        XCTAssertEqual(context.workspace, workspace)
        XCTAssertEqual(context.workerScope.id, 7)
        XCTAssertEqual(context.workerScope.slug, "worker-7")
        XCTAssertEqual(context.projectContext.defaultSimulatorName, "iPhone 17 Pro")
        XCTAssertEqual(
            context.artifactPaths.derivedDataRoot.path,
            "/tmp/ws/Glassdeck/.build/glassdeck-build/derived-data/worker-7"
        )
        XCTAssertTrue((context.processRunner as AnyObject) === runner)
        XCTAssertEqual(
            context.ghosttyBuilder.frameworkDestination.path,
            "/tmp/ws/Glassdeck/Frameworks/GhosttyKit.xcframework"
        )
    }
}
