import ArgumentParser
import XCTest
@testable import GlassdeckBuildCore

final class RootCommandTests: XCTestCase {
    func testRootCommandHasExpectedSubcommands() {
        let expected: [ParsableCommand.Type] = [
            BuildCommand.self,
            TestCommand.self,
            RunCommand.self,
            SimCommand.self,
            DockerCommand.self,
            ArtifactsCommand.self,
            DoctorCommand.self,
            DepsGhosttyCommand.self
        ]
        let configured = RootCommand.configuration.subcommands
        XCTAssertEqual(configured.count, expected.count)
        for type in expected {
            XCTAssertTrue(configured.contains(where: { String(describing: $0) == String(describing: type) }))
        }
    }

    func testRootCommandSupportsBuildParsing() throws {
        _ = try RootCommand.parseAsRoot(["build", "--scheme", "Smoke"])
    }
}
