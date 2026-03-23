import ArgumentParser
import Foundation

public struct SimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sim",
        abstract: "Manage simulator lifecycle and fixture environment."
    )

    public enum Action: String, ExpressibleByArgument {
        case boot
        case setEnv = "set-env"
        case unsetEnv = "unset-env"
        case copyText = "copy-text"
        case copyFile = "copy-file"
    }

    @Argument(help: "Simulator action to perform.")
    var action: Action = .boot

    @Option(help: "Simulator name or identifier for targeted actions.")
    var simulator: String = "iPhone 17"

    @Option(name: .long, help: "SSH host for set-env.")
    var host: String?

    @Option(name: .long, help: "SSH port for set-env.")
    var port: Int = 22222

    @Option(name: .long, help: "SSH username for set-env.")
    var user: String = "glassdeck"

    @Option(name: .long, help: "SSH password for set-env.")
    var password: String = "glassdeck"

    @Option(name: .customLong("key-path"), help: "SSH private key path for set-env or copy-file.")
    var keyPath: String?

    @Option(name: .customLong("text"), help: "Text payload for copy-text.")
    var text: String?

    @Option(name: .customLong("file"), help: "File payload for copy-file.")
    var file: String?

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    public init() {}

    public mutating func run() async throws {
        let workspace = WorkspaceContext.current()
        let processRunner = DefaultProcessRunner()
        let locator = SimulatorLocator(processRunner: processRunner)
        let simulatorIdentifier = try await locator.resolve(simulator)
        let boot = SimulatorBoot(processRunner: processRunner)
        let clipboard = SimulatorClipboard()

        let invocations: [ProcessInvocation]
        switch action {
        case .boot:
            invocations = try boot.bootInvocationChain(simulatorIdentifier: simulatorIdentifier)
        case .setEnv:
            let resolvedKeyPath = keyPath ?? CommandSupport
                .defaultFixtureConfiguration(workspace: workspace)
                .privateKeyPath
            guard let host else {
                throw ValidationError("--host is required for set-env.")
            }
            let environment = SimulatorEnvironment(
                host: host,
                port: port,
                username: user,
                password: password,
                keyPath: resolvedKeyPath
            )
            invocations = environment.launchctlSetenvInvocations(simulatorIdentifier: simulatorIdentifier)
        case .unsetEnv:
            let resolvedKeyPath = keyPath ?? CommandSupport
                .defaultFixtureConfiguration(workspace: workspace)
                .privateKeyPath
            let environment = SimulatorEnvironment(
                host: host ?? "127.0.0.1",
                port: port,
                username: user,
                password: password,
                keyPath: resolvedKeyPath
            )
            invocations = environment.launchctlUnsetenvInvocations(simulatorIdentifier: simulatorIdentifier)
        case .copyText:
            guard let text else {
                throw ValidationError("--text is required for copy-text.")
            }
            invocations = [clipboard.copyTextInvocation(simulatorIdentifier: simulatorIdentifier, text: text)]
        case .copyFile:
            let resolvedFile = file ?? keyPath
            guard let resolvedFile else {
                throw ValidationError("--file is required for copy-file.")
            }
            invocations = [clipboard.copyFileInvocation(
                simulatorIdentifier: simulatorIdentifier,
                fileURL: URL(fileURLWithPath: resolvedFile)
            )]
        }

        if dryRun {
            for invocation in invocations {
                print(CommandLineRendering.render(invocation))
            }
            return
        }

        for invocation in invocations {
            _ = try await processRunner.run(invocation)
        }
        print(simulatorIdentifier)
    }
}
