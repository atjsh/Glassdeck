import XCTest
@testable import GlassdeckBuildCore

private final class RecordingGhosttyMaterializer: GhosttyMaterializing {
    private(set) var materializeCalls: [(source: URL, destination: URL)] = []
    private(set) var cacheCalls: [(source: URL, destination: URL)] = []
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func materializeFramework(from source: URL, to destination: URL) throws {
        materializeCalls.append((source, destination))
        try ensureDirectory(at: destination)
    }

    func cacheFramework(from source: URL, to destination: URL) throws {
        cacheCalls.append((source, destination))
        try ensureDirectory(at: destination)
    }

    private func ensureDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

final class GhosttyBuildTests: XCTestCase {
    func testCachePathIsCommitAndProfileScoped() {
        let cache = GhosttyArtifactCache(cacheRoot: URL(fileURLWithPath: "/tmp/cache"))
        let path = cache.xcframeworkPath(commit: "abcdef", profile: .releaseFast)

        XCTAssertEqual(path.path, "/tmp/cache/abcdef/release-fast/GhosttyKit.xcframework")
    }

    func testBuildInvocationUsesZigXcframeworkFlags() {
        let submodule = GhosttySubmodule(
            repositoryRoot: URL(fileURLWithPath: "/tmp/ghostty"),
            processRunner: ScriptedProcessRunner(responses: [])
        )
        let build = GhosttyBuild(
            submodule: submodule,
            cache: GhosttyArtifactCache(cacheRoot: URL(fileURLWithPath: "/tmp/cache")),
            processRunner: ScriptedProcessRunner(responses: []),
            frameworkDestination: URL(fileURLWithPath: "/tmp/Frameworks/GhosttyKit.xcframework")
        )

        let invocation = build.buildInvocation(profile: .debug)
        XCTAssertEqual(invocation.executable, "/usr/bin/env")
        XCTAssertTrue(invocation.arguments.contains("zig"))
        XCTAssertTrue(invocation.arguments.contains("-Demit-xcframework=true"))
        XCTAssertTrue(invocation.arguments.contains("-Demit-macos-app=false"))
        XCTAssertTrue(invocation.arguments.contains("-Dxcframework-target=universal"))
        XCTAssertTrue(invocation.arguments.contains("-Di18n=false"))
        XCTAssertTrue(invocation.arguments.contains("-Doptimize=Debug"))
    }

    func testPrepareSurfacesBuildStdoutAndStderrOnFailure() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-ghostty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let revisionRunner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "deadbeef\n"))
            ]
        )
        let buildRunner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(
                    result: ProcessResult(
                        exitCode: 1,
                        standardOutput: "building ghostty",
                        standardError: "zig failed"
                    ),
                    error: ProcessRunnerError.nonzeroExit(
                        ProcessResult(
                            exitCode: 1,
                            standardOutput: "building ghostty",
                            standardError: "zig failed"
                        )
                    )
                )
            ]
        )
        let build = GhosttyBuild(
            submodule: GhosttySubmodule(
                repositoryRoot: tempRoot,
                processRunner: revisionRunner
            ),
            cache: GhosttyArtifactCache(cacheRoot: tempRoot.appendingPathComponent("cache")),
            processRunner: buildRunner,
            frameworkDestination: tempRoot.appendingPathComponent("Frameworks/GhosttyKit.xcframework")
        )

        do {
            _ = try await build.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as GhosttyBuildError {
            let message = try XCTUnwrap(error.errorDescription)
            XCTAssertTrue(message.contains("exit code 1"))
            XCTAssertTrue(message.contains("building ghostty"))
            XCTAssertTrue(message.contains("zig failed"))
        }
    }

    func testPrepareSkipsMaterializeWhenMarkerMatchesCacheAndDestination() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let revisionRunner = ScriptedProcessRunner(
            responses: [ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "deadbeef\n"))]
        )
        let buildRunner = ScriptedProcessRunner(responses: [])
        let materializer = RecordingGhosttyMaterializer()
        let build = GhosttyBuild(
            submodule: GhosttySubmodule(repositoryRoot: tempRoot, processRunner: revisionRunner),
            cache: GhosttyArtifactCache(cacheRoot: tempRoot.appendingPathComponent("cache")),
            materializer: materializer,
            processRunner: buildRunner,
            frameworkDestination: tempRoot.appendingPathComponent("Frameworks/GhosttyKit.xcframework")
        )
        let cachedFramework = build.cache.xcframeworkPath(commit: "deadbeef", profile: .debug)
        try FileManager.default.createDirectory(at: cachedFramework, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: build.frameworkDestination, withIntermediateDirectories: true)
        try writeState(
            GhosttyMaterializationState(commit: "deadbeef", profile: .debug),
            to: build.materializationStatePath
        )

        let destination = try await build.prepare()

        XCTAssertEqual(destination.path, build.frameworkDestination.path)
        XCTAssertTrue(materializer.materializeCalls.isEmpty)
        XCTAssertTrue(materializer.cacheCalls.isEmpty)
        XCTAssertTrue(buildRunner.calls.isEmpty)
    }

    func testPrepareRematerializesWhenMarkerDoesNotMatch() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let revisionRunner = ScriptedProcessRunner(
            responses: [ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "deadbeef\n"))]
        )
        let buildRunner = ScriptedProcessRunner(responses: [])
        let materializer = RecordingGhosttyMaterializer()
        let build = GhosttyBuild(
            submodule: GhosttySubmodule(repositoryRoot: tempRoot, processRunner: revisionRunner),
            cache: GhosttyArtifactCache(cacheRoot: tempRoot.appendingPathComponent("cache")),
            materializer: materializer,
            processRunner: buildRunner,
            frameworkDestination: tempRoot.appendingPathComponent("Frameworks/GhosttyKit.xcframework")
        )
        let cachedFramework = build.cache.xcframeworkPath(commit: "deadbeef", profile: .debug)
        try FileManager.default.createDirectory(at: cachedFramework, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: build.frameworkDestination, withIntermediateDirectories: true)
        try writeState(
            GhosttyMaterializationState(commit: "old-revision", profile: .debug),
            to: build.materializationStatePath
        )

        _ = try await build.prepare()

        XCTAssertEqual(materializer.materializeCalls.count, 1)
        XCTAssertEqual(materializer.materializeCalls.first?.source.path, cachedFramework.path)
        XCTAssertTrue(buildRunner.calls.isEmpty)
    }

    func testPrepareRebuildsWhenCacheMissingAndWritesStateMarker() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let builtFramework = tempRoot
            .appendingPathComponent("macos")
            .appendingPathComponent("GhosttyKit.xcframework")
        try FileManager.default.createDirectory(at: builtFramework, withIntermediateDirectories: true)

        let revisionRunner = ScriptedProcessRunner(
            responses: [ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "deadbeef\n"))]
        )
        let buildRunner = ScriptedProcessRunner(
            responses: [ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "ok\n"))]
        )
        let materializer = RecordingGhosttyMaterializer()
        let build = GhosttyBuild(
            submodule: GhosttySubmodule(repositoryRoot: tempRoot, processRunner: revisionRunner),
            cache: GhosttyArtifactCache(cacheRoot: tempRoot.appendingPathComponent("cache")),
            materializer: materializer,
            processRunner: buildRunner,
            frameworkDestination: tempRoot.appendingPathComponent("Frameworks/GhosttyKit.xcframework")
        )

        _ = try await build.prepare(profile: .releaseFast)

        let cachedFramework = build.cache.xcframeworkPath(commit: "deadbeef", profile: .releaseFast)
        XCTAssertEqual(buildRunner.calls.count, 1)
        XCTAssertEqual(materializer.cacheCalls.count, 1)
        XCTAssertEqual(materializer.cacheCalls.first?.destination.path, cachedFramework.path)
        XCTAssertEqual(materializer.materializeCalls.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: build.materializationStatePath.path))
    }

    private func makeTempRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-ghostty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    private func writeState(_ state: GhosttyMaterializationState, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: path, options: .atomic)
    }
}
