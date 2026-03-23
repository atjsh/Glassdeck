import Foundation

public enum GhosttyBuildError: Error, LocalizedError {
    case buildFailed(ProcessResult)

    public var errorDescription: String? {
        switch self {
        case let .buildFailed(result):
            var segments = ["Ghostty build failed with exit code \(result.exitCode)."]
            let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stdout.isEmpty {
                segments.append("stdout:\n\(stdout)")
            }
            if !stderr.isEmpty {
                segments.append("stderr:\n\(stderr)")
            }
            return segments.joined(separator: "\n\n")
        }
    }
}

public final class GhosttyBuild {
    public let submodule: GhosttySubmodule
    public let cache: GhosttyArtifactCache
    public let materializer: GhosttyMaterializer
    public let processRunner: ProcessRunner
    public let frameworkDestination: URL
    public let zigExecutable: String
    public let fileManager: FileManager

    public init(
        submodule: GhosttySubmodule,
        cache: GhosttyArtifactCache,
        materializer: GhosttyMaterializer = GhosttyMaterializer(),
        processRunner: ProcessRunner = DefaultProcessRunner(),
        frameworkDestination: URL,
        zigExecutable: String = "/usr/bin/env",
        fileManager: FileManager = .default
    ) {
        self.submodule = submodule
        self.cache = cache
        self.materializer = materializer
        self.processRunner = processRunner
        self.frameworkDestination = frameworkDestination
        self.zigExecutable = zigExecutable
        self.fileManager = fileManager
    }

    public func buildInvocation(profile: GhosttyBuildProfile) -> ProcessInvocation {
        ProcessInvocation(
            executable: zigExecutable,
            arguments: [
                "zig",
                "build",
                "-Demit-xcframework=true",
                "-Demit-macos-app=false",
                "-Dxcframework-target=universal",
                "-Di18n=false",
                "-Doptimize=\(profile.zigOptimize)",
            ],
            workingDirectory: submodule.repositoryRoot
        )
    }

    public func prepare(profile: GhosttyBuildProfile = .debug) async throws -> URL {
        try submodule.validateExists()
        let commit = try await submodule.currentRevision()
        let cachedFramework = cache.xcframeworkPath(commit: commit, profile: profile)

        if fileManager.fileExists(atPath: cachedFramework.path) {
            try materializer.materializeFramework(from: cachedFramework, to: frameworkDestination)
            return frameworkDestination
        }

        do {
            _ = try await processRunner.run(buildInvocation(profile: profile))
        } catch let ProcessRunnerError.nonzeroExit(result) {
            throw GhosttyBuildError.buildFailed(result)
        }
        let builtFramework = submodule.repositoryRoot
            .appendingPathComponent("macos")
            .appendingPathComponent("GhosttyKit.xcframework")
        try materializer.cacheFramework(from: builtFramework, to: cachedFramework)
        try materializer.materializeFramework(from: cachedFramework, to: frameworkDestination)
        return frameworkDestination
    }
}
