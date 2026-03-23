import ArgumentParser
import Foundation

public struct RootCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "glassdeck-build",
        abstract: "Build and test orchestration entry point.",
        subcommands: [
            BuildCommand.self,
            TestCommand.self,
            RunCommand.self,
            SimCommand.self,
            DockerCommand.self,
            ArtifactsCommand.self,
            DoctorCommand.self,
            DepsGhosttyCommand.self,
        ],
        defaultSubcommand: BuildCommand.self
    )

    public init() {}

    public func run() async throws {
        throw CleanExit.helpRequest()
    }
}
