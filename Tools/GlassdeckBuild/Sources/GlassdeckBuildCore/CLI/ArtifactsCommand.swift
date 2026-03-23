import ArgumentParser
import Foundation

public struct ArtifactsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "artifacts",
        abstract: "Inspect or index generated artifacts."
    )

    @Option(help: "Command to inspect artifacts for.")
    var command: String = "build"

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    public init() {}

    public mutating func run() async throws {
        let workspace = WorkspaceContext.current()
        let artifactPaths = CommandSupport.artifactPaths(
            workspace: workspace,
            worker: CommandSupport.workerScope(id: worker)
        )
        let target = artifactPaths.artifactsRoot
            .appendingPathComponent(command)
            .appendingPathComponent("latest")

        if dryRun {
            print(target.path)
            return
        }

        guard FileManager.default.fileExists(atPath: target.path) else {
            throw ValidationError("No latest artifact directory exists at \(target.path)")
        }

        print(target.path)
        let layout = ArtifactLayout(artifactRoot: target)
        let existingPaths = layout.stableInspectionPaths.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if !existingPaths.isEmpty {
            for path in existingPaths {
                print(path.path)
            }
        }

        let summary = layout.summary
        if let content = try? String(contentsOf: summary, encoding: .utf8) {
            print(content)
        }
    }
}
