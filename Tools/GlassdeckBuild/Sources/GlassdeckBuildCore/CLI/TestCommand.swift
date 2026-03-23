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

    func resolvedAction() throws -> XcodeAction {
        if buildForTesting && testWithoutBuilding {
            throw ValidationError("--build-for-testing and --test-without-building are mutually exclusive.")
        }

        if buildForTesting {
            return .buildForTesting
        }
        if testWithoutBuilding {
            return .testWithoutBuilding
        }
        return .test
    }

    func additionalTestArguments() -> [String] {
        var additionalArguments: [String] = []
        for item in onlyTesting {
            additionalArguments.append(contentsOf: ["-only-testing", item])
        }
        return additionalArguments
    }

    func executionRequest() throws -> XcodeCommandRequest {
        XcodeCommandRequest(
            action: try resolvedAction(),
            scheme: SchemeSelector(rawValue: scheme),
            additionalArguments: additionalTestArguments()
        )
    }

    func previewInvocation(using context: CommandExecutionContext) throws -> ProcessInvocation {
        let request = try executionRequest()
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
        let request = try executionRequest()
        let previewInvocation = try previewInvocation(using: context)

        if dryRun {
            print(CommandLineRendering.render(previewInvocation))
            return
        }

        _ = try await context.ghosttyBuilder.prepare()
        let result = try await invoker.execute(request)
        print(result.summaryPath.path)
    }
}
