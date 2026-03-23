import Darwin
import Foundation
import XCTest
@testable import GlassdeckBuildCore

private final class StdoutCapture {
    private let originalStdout: Int32
    private let pipeRead: Int32
    private let pipeWrite: Int32

    init() {
        originalStdout = dup(STDOUT_FILENO)
        var pipes = [Int32](repeating: 0, count: 2)
        _ = pipes.withUnsafeMutableBufferPointer { pointer in
            pipe(pointer.baseAddress!)
        }
        pipeRead = pipes[0]
        pipeWrite = pipes[1]
        dup2(pipeWrite, STDOUT_FILENO)
        close(pipeWrite)
    }

    func endAndRead() -> String {
        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        let handle = FileHandle(fileDescriptor: pipeRead)
        let output = handle.readDataToEndOfFile()
        close(pipeRead)
        return String(decoding: output, as: UTF8.self)
    }
}

final class ArtifactsCommandTests: XCTestCase {
    func testArtifactsCommandDryRunPrintsStableLatestPath() async throws {
        let root = try makeArtifactsWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let previousDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(root.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previousDirectory) }

        var command = try ArtifactsCommand.parse(["--command", "test", "--worker", "7", "--dry-run"])

        let capture = StdoutCapture()
        try await command.run()
        let output = capture.endAndRead().trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = ArtifactPaths(
            repoRoot: root.appendingPathComponent("Glassdeck"),
            worker: WorkerScope(id: 7).slug
        ).artifactsRoot
            .appendingPathComponent("test")
            .appendingPathComponent("latest")
            .path

        XCTAssertEqual(output, expected)
    }

    func testArtifactsCommandPrintsArtifactRootStablePathsAndSummary() async throws {
        let root = try makeArtifactsWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let previousDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(root.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previousDirectory) }

        let artifactPaths = ArtifactPaths(repoRoot: root.appendingPathComponent("Glassdeck"))
        let run = artifactPaths.makeRun(command: "test", runId: "ui", timestamp: "20260323-120000")
        let paths = artifactPaths.paths(for: run)

        try FileManager.default.createDirectory(at: paths.artifactRoot, withIntermediateDirectories: true)
        try artifactPaths.ensureDirectoryLayout()
        try artifactPaths.ensureCommandRoots(for: run.command)
        try artifactPaths.updateLatestAlias(for: run)
        try "summary body".write(to: paths.layout.summary, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: paths.layout.log.path, contents: Data(), attributes: nil)
        try FileManager.default.createDirectory(at: paths.layout.diagnosticsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: paths.layout.resultBundle.path,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: paths.layout.screen.path,
            contents: Data(),
            attributes: nil
        )
        FileManager.default.createFile(
            atPath: paths.layout.terminal.path,
            contents: Data(),
            attributes: nil
        )
        FileManager.default.createFile(
            atPath: paths.layout.uiTree.path,
            contents: Data(),
            attributes: nil
        )

        var command = try ArtifactsCommand.parse(["--command", "test"])

        let capture = StdoutCapture()
        try await command.run()
        let output = capture.endAndRead()
        let latestPath = artifactPaths.artifactsRoot
            .appendingPathComponent("test")
            .appendingPathComponent("latest")

        XCTAssertTrue(output.contains(latestPath.path))
        XCTAssertTrue(output.contains(ArtifactLayout.logFileName))
        XCTAssertTrue(output.contains(ArtifactLayout.resultBundleFileName))
        XCTAssertTrue(output.contains(ArtifactLayout.diagnosticsDirectoryName))
        XCTAssertTrue(output.contains(ArtifactLayout.summaryFileName))
        XCTAssertTrue(output.contains(ArtifactLayout.screenFileName))
        XCTAssertTrue(output.contains(ArtifactLayout.terminalFileName))
        XCTAssertTrue(output.contains(ArtifactLayout.uiTreeFileName))
        XCTAssertTrue(output.contains("summary body"))
    }
}

private func makeArtifactsWorkspaceRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gb-artifacts-cmd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Glassdeck/GlassdeckApp.xcodeproj"),
        withIntermediateDirectories: true
    )
    return root
}
