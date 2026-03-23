import XCTest
@testable import GlassdeckBuildCore

final class ArtifactIndexTests: XCTestCase {
    func testIndexBuilderAndManifestRoundTrip() throws {
        let run = ArtifactRun(
            command: "docker-key",
            runId: "run-1",
            timestamp: "20260101-000001"
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var builder = ArtifactIndexBuilder(
            command: "test",
            worker: "worker-a",
            run: run,
            startedAt: start,
            clock: { Date(timeIntervalSince1970: 1_700_000_005) }
        )

        builder.record(
            phase: "prompt-visible",
            kind: "screenshot",
            relativePath: "artifacts/terminal.png",
            anomaly: nil
        )
        builder.record(
            phase: "command-injected",
            kind: "log",
            relativePath: "artifacts/stdout.log",
            anomaly: "truncated"
        )

        let index = builder.build(completedAt: Date(timeIntervalSince1970: 1_700_000_010))

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-index-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let writer = ArtifactManifestWriter()
        let path = try writer.write(index, to: tempRoot)
        let loaded = try writer.readIndex(from: path)

        XCTAssertEqual(loaded.version, ArtifactIndex.currentVersion)
        XCTAssertEqual(loaded.command, "test")
        XCTAssertEqual(loaded.worker, "worker-a")
        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(loaded.entries[1].anomaly, "truncated")
        XCTAssertEqual(loaded.timestamp, start)
        XCTAssertEqual(loaded.completedAt, Date(timeIntervalSince1970: 1_700_000_010))
    }
}
