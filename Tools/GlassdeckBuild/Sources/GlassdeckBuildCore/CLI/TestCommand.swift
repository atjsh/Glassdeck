import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run tests through the native runner."
    )

    @Option(help: "Scheme alias or name to test.")
    var scheme: String = "unit"

    @Option(help: "Simulator name or identifier used for xcodebuild destination.")
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

    @Option(help: "xcodebuild output mode: filtered (default), full, or quiet.")
    var xcodeOutputMode: XcodeOutputMode = .filtered

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

    func executionRequest(simulatorIdentifier: String? = nil) throws -> XcodeCommandRequest {
        XcodeCommandRequest(
            action: try resolvedAction(),
            scheme: SchemeSelector(rawValue: scheme),
            simulatorIdentifier: simulatorIdentifier,
            additionalArguments: additionalTestArguments()
        )
    }

    func resolvedExecutionRequest(using processRunner: ProcessRunner) async throws -> XcodeCommandRequest {
        let simulatorIdentifier = try await SimulatorLocator(processRunner: processRunner).resolve(simulator)
        return try executionRequest(simulatorIdentifier: simulatorIdentifier)
    }

    func previewInvocation(
        using context: CommandExecutionContext,
        request: XcodeCommandRequest? = nil
    ) throws -> ProcessInvocation {
        let request = if let request {
            request
        } else {
            try executionRequest()
        }
        return context
            .xcodeCommandExecutor(outputMode: xcodeOutputMode.processOutputMode)
            .previewInvocation(for: request)
    }

    public mutating func run() async throws {
        let context = CommandSupport.executionContext(
            simulatorName: simulator,
            workerID: worker
        )
        let executor = context.xcodeCommandExecutor(outputMode: xcodeOutputMode.processOutputMode)
        let request = try await resolvedExecutionRequest(using: context.processRunner)
        let previewInvocation = try previewInvocation(using: context, request: request)

        if dryRun {
            print(CommandLineRendering.render(previewInvocation))
            return
        }

        _ = try await context.ghosttyBuilder.prepare()
        let result = try await executor.execute(request)
        print(result.summaryPath.path)
    }
}
