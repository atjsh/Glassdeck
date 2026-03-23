import Foundation
import XCTest
@testable import GlassdeckBuildCore

final class WorkspaceContextTests: XCTestCase {
    func testDefaultWorkspaceUsesCurrentDirectory() {
        let nestedPackageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let current = WorkspaceContext.current(at: nestedPackageDirectory.path)

        let expectedProjectRoot = nestedPackageDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expectedWorkspaceRoot = expectedProjectRoot.deletingLastPathComponent()

        XCTAssertEqual(current.workspaceRoot, expectedWorkspaceRoot)
        XCTAssertEqual(current.projectRoot, expectedProjectRoot)
    }

    func testWorkerScopeDefaults() {
        let worker = WorkerScope(id: 7)
        XCTAssertEqual(worker.slug, "worker-7")
        XCTAssertEqual(worker.name, "worker-7")
    }

    func testRunnerConfigCapturesArguments() {
        let workspace = WorkspaceContext.current()
        let worker = WorkerScope(id: 3, name: "alpha")
        let config = RunnerConfig(command: "test", arguments: ["--dry-run"], workspace: workspace, worker: worker, dryRun: true)

        XCTAssertEqual(config.command, "test")
        XCTAssertEqual(config.arguments, ["--dry-run"])
        XCTAssertEqual(config.worker, worker)
        XCTAssertTrue(config.dryRun)
    }
}
