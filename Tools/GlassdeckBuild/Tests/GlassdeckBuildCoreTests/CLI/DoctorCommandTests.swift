import XCTest
@testable import GlassdeckBuildCore

final class DoctorCommandTests: XCTestCase {
    func testDryRunPreviewIncludesResolvedProjectRoot() throws {
        let workspace = WorkspaceContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws"),
            projectRootName: "Glassdeck"
        )
        let command = try DoctorCommand.parse([])

        XCTAssertEqual(
            command.dryRunPreview(workspace: workspace),
            "doctor /tmp/ws/Glassdeck"
        )
    }
}
