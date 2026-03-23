import Foundation
import XCTest
@testable import GlassdeckBuildCore

final class PathLayoutTests: XCTestCase {
    func testWorkspaceAndProjectRoots() {
        let workspace = WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"), projectRootName: "Glassdeck")
        XCTAssertEqual(workspace.projectRoot.path, "/tmp/workspace/Glassdeck")
    }

    func testWorkerSpecificDerivedDataPaths() {
        let workspace = WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        let layout = PathLayout(workspace: workspace, worker: WorkerScope(id: 2, name: "ci"))
        XCTAssertEqual(layout.workerRoot.path, "/tmp/workspace/.build/glassdeck-build/derived-data/ci")
    }

    func testResultBundleAndArtifactPaths() {
        let workspace = WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        let layout = PathLayout(workspace: workspace, worker: WorkerScope(id: 1))
        let timestamp = "2026-03-23T1000"

        let results = layout.resultBundlePath(for: "test", timestamp: timestamp)
        let log = layout.logFilePath(for: "test", timestamp: timestamp)
        let artifacts = layout.artifactRoot(for: "test", timestamp: timestamp)
        let ghostty = layout.ghosttyCacheRoot()

        XCTAssertTrue(results.path.hasSuffix("/.build/glassdeck-build/test/results/\(timestamp).xcresult"))
        XCTAssertTrue(log.path.hasSuffix("/.build/glassdeck-build/test/logs/\(timestamp).log"))
        XCTAssertTrue(artifacts.path.hasSuffix("/.build/glassdeck-build/test/artifacts/\(timestamp)"))
        XCTAssertEqual(ghostty.path, "/tmp/workspace/.build/glassdeck-build/ghostty-cache")
    }
}
