import XCTest
@testable import GlassdeckBuildCore

final class ArtifactPathTests: XCTestCase {
    func testArtifactPathLayoutBuildsExpectedPaths() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-path-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try! FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let artifactPaths = ArtifactPaths(
            repoRoot: tempRoot,
            worker: "worker-a"
        )

        let run = artifactPaths.makeRun(command: "docker key", runId: "abc", timestamp: "20250101-000101")
        let paths = artifactPaths.paths(for: run)

        XCTAssertEqual(
            artifactPaths.derivedDataRoot.path,
            tempRoot
                .appendingPathComponent(".build")
                .appendingPathComponent("glassdeck-build")
                .appendingPathComponent("derived-data")
                .appendingPathComponent("worker-a")
                .path
        )
        XCTAssertEqual(paths.resultBundle.lastPathComponent, "20250101-000101-abc.xcresult")
        XCTAssertEqual(paths.resultLog.lastPathComponent, "20250101-000101-abc.log")
        XCTAssertEqual(
            paths.artifactRoot.lastPathComponent,
            "20250101-000101-abc"
        )
        XCTAssertEqual(paths.command, "docker-key")
    }

    func testArtifactPathLayoutCanAcceptInjectedTimestamp() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-path-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)
        let artifactPaths = ArtifactPaths(
            repoRoot: tempRoot,
            worker: "worker-a",
            nowProvider: { fixedDate }
        )
        let timestamp = artifactPaths.formatRunTimestamp(fixedDate)
        let run = artifactPaths.makeRun(command: "docker key", runId: "abc", timestamp: timestamp)
        let paths = artifactPaths.paths(for: run)

        XCTAssertEqual(timestamp, "20250615-150640")
        XCTAssertEqual(paths.resultBundle.path, tempRoot
            .appendingPathComponent(".build/glassdeck-build/results")
            .appendingPathComponent("docker-key")
            .appendingPathComponent("\(timestamp)-abc.xcresult")
            .path)
    }

    func testLatestAliasTargetsRunDirectory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-path-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let artifactPaths = ArtifactPaths(repoRoot: tempRoot)
        let run = ArtifactRun(
            command: "docker-key",
            runId: "abc",
            timestamp: "20250101-010101"
        )
        let expectedCommandRoot = artifactPaths.artifactsRoot
            .appendingPathComponent(run.command)
        let runPaths = artifactPaths.paths(for: run)
        try artifactPaths.ensureDirectoryLayout()
        try artifactPaths.ensureCommandRoots(for: run.command)
        try FileManager.default.createDirectory(at: runPaths.artifactRoot, withIntermediateDirectories: true)
        try artifactPaths.updateLatestAlias(for: run)

        let aliasURL = expectedCommandRoot.appendingPathComponent("latest")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: aliasURL.path)
        XCTAssertEqual(aliasURL.appendingPathComponent(destination).lastPathComponent, runPaths.artifactRoot.lastPathComponent)
    }
}
