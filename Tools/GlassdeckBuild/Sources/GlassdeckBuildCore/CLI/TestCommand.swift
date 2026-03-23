import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run tests through the native runner."
    )

    @Option(help: "Scheme alias or name to test.")
    var scheme: String = "unit"

    @Option(help: "Simulator name used for xcodebuild destination.")
    var simulator: String = "iPhone 17"

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    @Flag(help: "Run build-for-testing instead of test.")
    var buildForTesting: Bool = false

    @Flag(help: "Run test-without-building instead of test.")
    var testWithoutBuilding: Bool = false

    @Option(name: .customLong("only-testing"), parsing: .upToNextOption, help: "Forward -only-testing arguments to xcodebuild.")
    var onlyTesting: [String] = []

    public init() {}

    public mutating func run() async throws {
        if buildForTesting && testWithoutBuilding {
            throw ValidationError("--build-for-testing and --test-without-building are mutually exclusive.")
        }

        let workspace = WorkspaceContext.current()
        let workerScope = CommandSupport.workerScope(id: worker)
        let projectContext = CommandSupport.projectContext(workspace: workspace, simulatorName: simulator)
        let artifactPaths = CommandSupport.artifactPaths(workspace: workspace, worker: workerScope)
        let invoker = XcodeInvoker(
            projectContext: projectContext,
            artifactPaths: artifactPaths
        )

        let action: XcodeAction = if buildForTesting {
            .buildForTesting
        } else if testWithoutBuilding {
            .testWithoutBuilding
        } else {
            .test
        }

        var additionalArguments: [String] = []
        for item in onlyTesting {
            additionalArguments.append(contentsOf: ["-only-testing", item])
        }

        let request = XcodeCommandRequest(
            action: action,
            scheme: SchemeSelector(rawValue: scheme),
            additionalArguments: additionalArguments
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
