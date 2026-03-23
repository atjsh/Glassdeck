import Foundation

public struct DoctorChecks {
    public let toolchainChecks: ToolchainChecks
    public let repoStateChecks: RepoStateChecks

    public init(
        toolchainChecks: ToolchainChecks = ToolchainChecks(),
        repoStateChecks: RepoStateChecks = RepoStateChecks()
    ) {
        self.toolchainChecks = toolchainChecks
        self.repoStateChecks = repoStateChecks
    }

    public func run(repoRoot: URL) -> DiagnosticsReport {
        let issues = toolchainChecks.run() + repoStateChecks.run(at: repoRoot)
        return DiagnosticsReport(issues: issues)
    }
}
