import XCTest
@testable import GlassdeckBuildCore

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
}
