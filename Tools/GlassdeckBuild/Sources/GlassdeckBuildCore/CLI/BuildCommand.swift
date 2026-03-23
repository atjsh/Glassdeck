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

    func executionRequest() -> XcodeCommandRequest {
        XcodeCommandRequest(
            action: buildForTesting ? .buildForTesting : .build,
            scheme: SchemeSelector(rawValue: scheme)
        )
    }

    func previewInvocation(using context: CommandExecutionContext) -> ProcessInvocation {
        let request = executionRequest()
        let previewRun = context.artifactPaths.makeRun(
            command: request.action.artifactCommand,
            runId: request.scheme.artifactRunID
        )
        return XcodeInvoker(
            projectContext: context.projectContext,
            processRunner: context.processRunner,
            artifactPaths: context.artifactPaths
        ).makeInvocation(
            for: request,
            resultBundlePath: context.artifactPaths.paths(for: previewRun).resultBundle
        )
    }

    public mutating func run() async throws {
        let context = CommandSupport.executionContext(
            simulatorName: simulator,
            workerID: worker
        )
        let invoker = XcodeInvoker(
            projectContext: context.projectContext,
            processRunner: context.processRunner,
            artifactPaths: context.artifactPaths
        )
        let request = executionRequest()
        let previewInvocation = previewInvocation(using: context)

        if dryRun {
            print(CommandLineRendering.render(previewInvocation))
            return
        }

        _ = try await context.ghosttyBuilder.prepare()
        let result = try await invoker.execute(request)
        print(result.summaryPath.path)
    }
}
