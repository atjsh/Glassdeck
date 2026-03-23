import Foundation

enum CommandSupport {
    static func workerScope(id: Int) -> WorkerScope {
        WorkerScope(id: id)
    }

    static func executionContext(
        workspace: WorkspaceContext = .current(),
        simulatorName: String,
        workerID: Int,
        processRunner: ProcessRunner = DefaultProcessRunner()
    ) -> CommandExecutionContext {
        let workerScope = workerScope(id: workerID)
        let artifactPaths = artifactPaths(workspace: workspace, worker: workerScope)
        return CommandExecutionContext(
            workspace: workspace,
            workerScope: workerScope,
            projectContext: projectContext(workspace: workspace, simulatorName: simulatorName),
            artifactPaths: artifactPaths,
            processRunner: processRunner,
            ghosttyBuilder: ghosttyBuilder(
                workspace: workspace,
                worker: workerScope,
                processRunner: processRunner
            )
        )
    }

    static func artifactPaths(
        workspace: WorkspaceContext,
        worker: WorkerScope
    ) -> ArtifactPaths {
        ArtifactPaths(
            repoRoot: workspace.projectRoot,
            worker: worker.slug
        )
    }

    static func projectContext(
        workspace: WorkspaceContext,
        simulatorName: String
    ) -> XcodeProjectContext {
        XcodeProjectContext(
            workspace: workspace,
            defaultSimulatorName: simulatorName
        )
    }

    static func ghosttyBuilder(
        workspace: WorkspaceContext,
        worker: WorkerScope,
        processRunner: ProcessRunner = DefaultProcessRunner()
    ) -> GhosttyBuild {
        GhosttyBuild(
            submodule: GhosttySubmodule(
                repositoryRoot: workspace.projectRoot
                    .appendingPathComponent("Vendor/ghostty-fork"),
                processRunner: processRunner
            ),
            cache: GhosttyArtifactCache(
                cacheRoot: artifactPaths(workspace: workspace, worker: worker).ghosttyCacheRoot
            ),
            processRunner: processRunner,
            frameworkDestination: workspace.projectRoot
                .appendingPathComponent("Frameworks/GhosttyKit.xcframework")
        )
    }

    static func defaultDockerConfiguration(
        workspace: WorkspaceContext,
        worker: WorkerScope
    ) -> DockerComposeConfiguration {
        DockerComposeConfiguration(
            projectName: "glassdeck-\(worker.slug)",
            composeFile: workspace.projectRoot
                .appendingPathComponent("Scripts/docker/ssh-compose.yml"),
            runtimeDirectory: workspace.projectRoot
        )
    }

    static func defaultFixtureConfiguration(workspace: WorkspaceContext) -> LiveSSHFixtureConfiguration {
        LiveSSHFixtureConfiguration(
            dockerHostPort: 22222,
            username: "glassdeck",
            password: "glassdeck",
            privateKeyPath: workspace.projectRoot
                .appendingPathComponent("Scripts/docker/fixtures/keys/glassdeck_ed25519")
                .path
        )
    }
}
