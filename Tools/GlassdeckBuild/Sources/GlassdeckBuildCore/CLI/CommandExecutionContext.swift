import Foundation

public struct CommandExecutionContext {
    public let workspace: WorkspaceContext
    public let workerScope: WorkerScope
    public let projectContext: XcodeProjectContext
    public let artifactPaths: ArtifactPaths
    public let processRunner: ProcessRunner
    public let ghosttyBuilder: GhosttyBuild

    public init(
        workspace: WorkspaceContext,
        workerScope: WorkerScope,
        projectContext: XcodeProjectContext,
        artifactPaths: ArtifactPaths,
        processRunner: ProcessRunner,
        ghosttyBuilder: GhosttyBuild
    ) {
        self.workspace = workspace
        self.workerScope = workerScope
        self.projectContext = projectContext
        self.artifactPaths = artifactPaths
        self.processRunner = processRunner
        self.ghosttyBuilder = ghosttyBuilder
    }

    public func xcodeCommandExecutor(
        outputMode: ProcessOutputMode = .captureAndStreamTimestampedFiltered(.xcodebuild)
    ) -> XcodeCommandExecutor {
        XcodeCommandExecutor(
            context: self,
            outputMode: outputMode
        )
    }
}
