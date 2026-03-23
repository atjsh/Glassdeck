import ArgumentParser
import Foundation

public struct BuildCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Prepare simulator artifacts via xcodebuild."
    )

    @Option(help: "Scheme alias or name to build.")
    var scheme: String = "app"

    @Option(help: "Simulator name or identifier used for xcodebuild destination.")
    var simulator: String = "iPhone 17"

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Run xcodebuild build-for-testing instead of build.")
    var buildForTesting: Bool = false

    @Option(help: "xcodebuild output mode: filtered (default), full, or quiet.")
    var xcodeOutputMode: XcodeOutputMode = .filtered

    public init() {}

    func executionRequest(simulatorIdentifier: String? = nil) -> XcodeCommandRequest {
        XcodeCommandRequest(
            action: buildForTesting ? .buildForTesting : .build,
            scheme: SchemeSelector(rawValue: scheme),
            simulatorIdentifier: simulatorIdentifier
        )
    }

    func resolvedExecutionRequest(using processRunner: ProcessRunner) async throws -> XcodeCommandRequest {
        let simulatorIdentifier = try await SimulatorLocator(processRunner: processRunner).resolve(simulator)
        return executionRequest(simulatorIdentifier: simulatorIdentifier)
    }

    func previewInvocation(
        using context: CommandExecutionContext,
        request: XcodeCommandRequest? = nil
    ) -> ProcessInvocation {
        let request = request ?? executionRequest()
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
        let previewInvocation = previewInvocation(using: context, request: request)

        if dryRun {
            print(CommandLineRendering.render(previewInvocation))
            return
        }

        _ = try await context.ghosttyBuilder.prepare()
        let result = try await executor.execute(request)
        print(result.summaryPath.path)
    }
}
