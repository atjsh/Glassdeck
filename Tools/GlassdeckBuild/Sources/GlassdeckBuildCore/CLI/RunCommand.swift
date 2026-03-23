import ArgumentParser
import Foundation

public struct RunCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run app or utility command."
    )

    @Option(help: "Scheme alias or name to run.")
    var scheme: String = "app"

    @Option(help: "Simulator name or identifier.")
    var simulator: String = "iPhone 17"

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    public init() {}

    public mutating func run() async throws {
        let workspace = WorkspaceContext.current()
        let workerScope = CommandSupport.workerScope(id: worker)
        let processRunner = DefaultProcessRunner()
        let locator = SimulatorLocator(processRunner: processRunner)
        let simulatorIdentifier = try await locator.resolve(simulator)
        let boot = SimulatorBoot(processRunner: processRunner)
        let projectContext = CommandSupport.projectContext(workspace: workspace, simulatorName: simulator)
        let artifactPaths = CommandSupport.artifactPaths(workspace: workspace, worker: workerScope)
        let invoker = XcodeInvoker(
            projectContext: projectContext,
            processRunner: processRunner,
            artifactPaths: artifactPaths
        )

        let request = XcodeCommandRequest(
            action: .build,
            scheme: SchemeSelector(rawValue: scheme),
            simulatorIdentifier: simulatorIdentifier
        )

        let previewRun = artifactPaths.makeRun(command: "build", runId: request.scheme.artifactRunID)
        let previewBuildInvocation = invoker.makeInvocation(
            for: request,
            resultBundlePath: artifactPaths.paths(for: previewRun).resultBundle
        )
        let previewAppPath = projectContext.builtAppPath(derivedDataPath: artifactPaths.derivedDataRoot)
        let installInvocation = ProcessInvocation(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "install", simulatorIdentifier, previewAppPath.path],
            workingDirectory: workspace.projectRoot
        )
        let launchInvocation = ProcessInvocation(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "launch", simulatorIdentifier, projectContext.appBundleIdentifier],
            workingDirectory: workspace.projectRoot
        )

        if dryRun {
            print(CommandLineRendering.render(previewBuildInvocation))
            print(CommandLineRendering.render(installInvocation))
            print(CommandLineRendering.render(launchInvocation))
            return
        }

        _ = try await CommandSupport.ghosttyBuilder(
            workspace: workspace,
            worker: workerScope,
            processRunner: processRunner
        ).prepare()
        try await boot.boot(simulatorIdentifier: simulatorIdentifier)
        _ = try await invoker.execute(request)
        _ = try await processRunner.run(
            ProcessInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "install", simulatorIdentifier, projectContext.builtAppPath(derivedDataPath: artifactPaths.derivedDataRoot).path],
                workingDirectory: workspace.projectRoot
            )
        )
        _ = try await processRunner.run(
            ProcessInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "launch", simulatorIdentifier, projectContext.appBundleIdentifier],
                workingDirectory: workspace.projectRoot
            )
        )
        print(projectContext.appBundleIdentifier)
    }
}
