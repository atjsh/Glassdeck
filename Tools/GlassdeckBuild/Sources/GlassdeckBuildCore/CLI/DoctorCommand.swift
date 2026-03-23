import ArgumentParser
import Foundation

public struct DoctorCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Run developer toolchain checks."
    )

    @Flag(help: "Print generated command only.")
    var dryRun: Bool = false

    @Option(name: .long, help: "Worker index for scoped layouts.")
    var worker: Int = 0

    public init() {}

    public mutating func run() async throws {
        let workspace = WorkspaceContext.current()
        let report = DoctorChecks().run(repoRoot: workspace.projectRoot)

        if dryRun {
            print("doctor \(workspace.projectRoot.path)")
            return
        }

        print(report.renderText())
        if report.hasErrors {
            throw ValidationError("doctor found blocking errors")
        }
    }
}
