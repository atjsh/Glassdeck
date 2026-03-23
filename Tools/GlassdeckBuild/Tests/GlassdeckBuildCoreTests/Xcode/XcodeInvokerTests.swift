import XCTest
@testable import GlassdeckBuildCore

final class XcodeInvokerTests: XCTestCase {
    func testInvocationIncludesDestinationDerivedDataAndResultBundle() {
        let workspace = WorkspaceContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws"),
            projectRootName: "Glassdeck"
        )
        let projectContext = XcodeProjectContext(workspace: workspace)
        let artifactPaths = ArtifactPaths(
            repoRoot: projectContext.workspace.projectRoot,
            worker: "worker-0"
        )
        let invoker = XcodeInvoker(
            projectContext: projectContext,
            artifactPaths: artifactPaths
        )

        let request = XcodeCommandRequest(
            action: .testWithoutBuilding,
            scheme: .ui,
            simulatorIdentifier: "SIM-1234",
            environmentAssignments: ["SIMCTL_CHILD_FOO": "BAR"]
        )
        let invocation = invoker.makeInvocation(
            for: request,
            resultBundlePath: URL(fileURLWithPath: "/tmp/out.xcresult")
        )

        XCTAssertEqual(invocation.executable, "/usr/bin/xcodebuild")
        XCTAssertTrue(invocation.arguments.contains("test-without-building"))
        XCTAssertTrue(invocation.arguments.contains("GlassdeckAppUI"))
        XCTAssertTrue(invocation.arguments.contains("platform=iOS Simulator,id=SIM-1234"))
        XCTAssertTrue(invocation.arguments.contains("/tmp/out.xcresult"))
        XCTAssertTrue(invocation.arguments.contains("SIMCTL_CHILD_FOO=BAR"))
    }
}
