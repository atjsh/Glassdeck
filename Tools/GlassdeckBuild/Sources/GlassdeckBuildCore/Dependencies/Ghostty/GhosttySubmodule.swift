import Foundation

public struct GhosttySubmodule {
    public let repositoryRoot: URL
    public let processRunner: ProcessRunner

    public init(
        repositoryRoot: URL,
        processRunner: ProcessRunner = DefaultProcessRunner()
    ) {
        self.repositoryRoot = repositoryRoot
        self.processRunner = processRunner
    }

    public func currentRevision() async throws -> String {
        let invocation = ProcessInvocation(
            executable: "/usr/bin/git",
            arguments: ["-C", repositoryRoot.path, "rev-parse", "HEAD"]
        )
        let result = try await processRunner.run(invocation)
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validateExists() throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: repositoryRoot.path,
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else {
            throw NSError(
                domain: "GhosttySubmodule",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ghostty submodule is missing at \(repositoryRoot.path)"]
            )
        }
    }
}
