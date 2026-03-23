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

    func buildRequest(simulatorIdentifier: String) -> XcodeCommandRequest {
        XcodeCommandRequest(
            action: .build,
            scheme: SchemeSelector(rawValue: scheme),
            simulatorIdentifier: simulatorIdentifier
        )
    }

    func previewInvocations(
        using context: CommandExecutionContext,
        simulatorIdentifier: String
    ) -> [ProcessInvocation] {
        let request = buildRequest(simulatorIdentifier: simulatorIdentifier)
        let invoker = XcodeInvoker(
            projectContext: context.projectContext,
            processRunner: context.processRunner,
            artifactPaths: context.artifactPaths
        )
        let previewRun = context.artifactPaths.makeRun(
            command: request.action.artifactCommand,
            runId: request.scheme.artifactRunID
        )
        let previewBuildInvocation = invoker.makeInvocation(
            for: request,
            resultBundlePath: context.artifactPaths.paths(for: previewRun).resultBundle
        )
        let previewAppPath = context.projectContext.builtAppPath(
            derivedDataPath: context.artifactPaths.derivedDataRoot
        )
        let installInvocation = ProcessInvocation(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "install", simulatorIdentifier, previewAppPath.path],
            workingDirectory: context.workspace.projectRoot
        )
        let launchInvocation = ProcessInvocation(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "launch", simulatorIdentifier, context.projectContext.appBundleIdentifier],
            workingDirectory: context.workspace.projectRoot
        )
        return [previewBuildInvocation, installInvocation, launchInvocation]
    }

    public mutating func run() async throws {
        let processRunner = DefaultProcessRunner()
        let context = CommandSupport.executionContext(
            simulatorName: simulator,
            workerID: worker,
            processRunner: processRunner
        )
        let locator = SimulatorLocator(processRunner: processRunner)
        let simulatorIdentifier = try await locator.resolve(simulator)
        let boot = SimulatorBoot(processRunner: processRunner)
        let invoker = XcodeInvoker(
            projectContext: context.projectContext,
            processRunner: processRunner,
            artifactPaths: context.artifactPaths
        )
        let request = buildRequest(simulatorIdentifier: simulatorIdentifier)
        let previewChain = previewInvocations(
            using: context,
            simulatorIdentifier: simulatorIdentifier
        )

        if dryRun {
            for invocation in previewChain {
                print(CommandLineRendering.render(invocation))
            }
            return
        }

        _ = try await context.ghosttyBuilder.prepare()
        try await boot.boot(simulatorIdentifier: simulatorIdentifier)
        _ = try await invoker.execute(request)
        _ = try await processRunner.run(
            ProcessInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "install", simulatorIdentifier, context.projectContext.builtAppPath(derivedDataPath: context.artifactPaths.derivedDataRoot).path],
                workingDirectory: context.workspace.projectRoot
            )
        )
        _ = try await processRunner.run(
            ProcessInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "launch", simulatorIdentifier, context.projectContext.appBundleIdentifier],
                workingDirectory: context.workspace.projectRoot
            )
        )
        print(context.projectContext.appBundleIdentifier)
    }
}
