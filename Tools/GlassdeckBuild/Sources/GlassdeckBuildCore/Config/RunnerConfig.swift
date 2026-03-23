import Foundation

public struct RunnerConfig: Equatable, Sendable {
    public let command: String
    public let arguments: [String]
    public let workspace: WorkspaceContext
    public let worker: WorkerScope
    public let dryRun: Bool

    public init(
        command: String,
        arguments: [String] = [],
        workspace: WorkspaceContext = .current(),
        worker: WorkerScope = .default,
        dryRun: Bool = false
    ) {
        self.command = command
        self.arguments = arguments
        self.workspace = workspace
        self.worker = worker
        self.dryRun = dryRun
    }
}
