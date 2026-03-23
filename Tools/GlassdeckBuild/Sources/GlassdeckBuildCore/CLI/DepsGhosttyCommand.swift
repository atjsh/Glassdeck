import ArgumentParser
import Foundation

public struct DepsGhosttyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "deps",
        abstract: "Prepare dependency artifacts such as Ghostty.",
        subcommands: [GhosttyCommand.self],
        defaultSubcommand: GhosttyCommand.self
    )

    public init() {}

    public func run() async throws {
        throw CleanExit.helpRequest()
    }
}

extension DepsGhosttyCommand {
    public struct GhosttyCommand: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "ghostty",
            abstract: "Build, cache, and materialize GhosttyKit.xcframework."
        )

        @Option(name: .long, help: "Worker index for scoped layouts.")
        var worker: Int = 0

        @Flag(help: "Print generated command only.")
        var dryRun: Bool = false

        @Option(name: .long, help: "Ghostty build profile (debug or release-fast).")
        var profile: String = "debug"

        public init() {}

        public mutating func run() async throws {
            let workspace = WorkspaceContext.current()
            let workerScope = CommandSupport.workerScope(id: worker)
            let builder = CommandSupport.ghosttyBuilder(
                workspace: workspace,
                worker: workerScope
            )
            let selectedProfile: GhosttyBuildProfile = profile == "release-fast" ? .releaseFast : .debug
            let previewInvocation = builder.buildInvocation(profile: selectedProfile)

            if dryRun {
                print(CommandLineRendering.render(previewInvocation))
                return
            }

            let materialized = try await builder.prepare(profile: selectedProfile)
            print(materialized.path)
        }
    }
}
