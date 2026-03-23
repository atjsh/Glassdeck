import ArgumentParser
import Foundation

public struct BuildCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Prepare simulator artifacts via xcodebuild."
    )

    @Option(help: "Scheme alias or name to build.")
    var scheme: String = "app"

    @Option(help: "Simulator name used for xcodebuild destination.")
    var simulator: String = "iPhone 17"

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Run xcodebuild build-for-testing instead of build.")
    var buildForTesting: Bool = false

    public init() {}

    public mutating func run() async throws {
        let workspace = WorkspaceContext.current()
        let workerScope = CommandSupport.workerScope(id: worker)
        let projectContext = CommandSupport.projectContext(workspace: workspace, simulatorName: simulator)
        let artifactPaths = CommandSupport.artifactPaths(workspace: workspace, worker: workerScope)
        let invoker = XcodeInvoker(
            projectContext: projectContext,
            artifactPaths: artifactPaths
        )
        let request = XcodeCommandRequest(
            action: buildForTesting ? .buildForTesting : .build,
            scheme: SchemeSelector(rawValue: scheme)
        )

        let previewRun = artifactPaths.makeRun(
            command: request.action.artifactCommand,
            runId: request.scheme.artifactRunID
        )
        let previewInvocation = invoker.makeInvocation(
            for: request,
            resultBundlePath: artifactPaths.paths(for: previewRun).resultBundle
        )

        if dryRun {
            print(CommandLineRendering.render(previewInvocation))
            return
        }

        _ = try await CommandSupport.ghosttyBuilder(
            workspace: workspace,
            worker: workerScope
        ).prepare()
        let result = try await invoker.execute(request)
        print(result.summaryPath.path)
    }
}
