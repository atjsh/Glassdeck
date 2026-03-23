import ArgumentParser
import Foundation

public struct DockerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "docker",
        abstract: "Manage docker fixtures through Swift-native orchestration stubs."
    )

    public enum Action: String, ExpressibleByArgument {
        case up
        case down
        case status
        case smoke
    }

    @Argument(help: "Docker action to run.")
    var action: Action = .status

    @Flag(name: .customLong("leave-running"), help: "Do not stop the fixture after smoke tests.")
    var leaveRunning: Bool = false

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    public init() {}

    public mutating func run() async throws {
        let workspace = WorkspaceContext.current()
        let workerScope = CommandSupport.workerScope(id: worker)
        let processRunner = DefaultProcessRunner()
        let docker = DockerComposeController(
            processRunner: processRunner,
            configuration: CommandSupport.defaultDockerConfiguration(
                workspace: workspace,
                worker: workerScope
            )
        )
        let fixture = LiveSSHFixture(
            docker: docker,
            hostResolver: HostIPResolver(processRunner: processRunner),
            configuration: CommandSupport.defaultFixtureConfiguration(workspace: workspace)
        )

        let previewInvocation: ProcessInvocation
        switch action {
        case .up:
            previewInvocation = docker.upInvocation()
        case .down:
            previewInvocation = docker.downInvocation()
        case .status, .smoke:
            previewInvocation = docker.psInvocation()
        }

        if dryRun {
            print(CommandLineRendering.render(previewInvocation))
            return
        }

        switch action {
        case .up:
            let environment = try await fixture.start()
            print("\(environment.host):\(environment.port)")
        case .down:
            try await fixture.stop()
        case .status:
            if let containerIdentifier = try await docker.containerIdentifier() {
                let health = try await docker.containerHealth(containerIdentifier: containerIdentifier)
                print("\(containerIdentifier) \(health)")
            } else {
                print("not-running")
            }
        case .smoke:
            let environment = try await fixture.start()
            let client = SSHSmokeClient()
            do {
                let passwordResult = try await client.run(.password(
                    host: environment.host,
                    port: environment.port,
                    username: environment.username,
                    password: environment.password
                ))
                let keyResult = try await client.run(.privateKey(
                    host: environment.host,
                    port: environment.port,
                    username: environment.username,
                    privateKeyPath: environment.privateKeyPath
                ))
                print("password=\(passwordResult.exitStatus) key=\(keyResult.exitStatus)")
            } catch {
                if !leaveRunning {
                    try? await fixture.stop()
                }
                throw error
            }
            if !leaveRunning {
                try await fixture.stop()
            }
        }
    }
}
