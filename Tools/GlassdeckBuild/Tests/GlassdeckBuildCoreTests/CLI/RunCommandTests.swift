import XCTest
@testable import GlassdeckBuildCore

final class RunCommandTests: XCTestCase {
    func testPreviewInvocationsIncludeBuildInstallAndLaunch() throws {
        let command = try RunCommand.parse(["--scheme", "app"])
        let context = CommandSupport.executionContext(
            workspace: WorkspaceContext(workspaceRoot: URL(fileURLWithPath: "/tmp/ws"), projectRootName: "Glassdeck"),
            simulatorName: "iPhone 17",
            workerID: 1,
            processRunner: ScriptedProcessRunner(responses: [])
        )

        let invocations = command.previewInvocations(
            using: context,
            simulatorIdentifier: "SIM-1234"
        )

        XCTAssertEqual(invocations.count, 3)
        XCTAssertEqual(invocations[0].executable, "/usr/bin/xcodebuild")
        XCTAssertTrue(invocations[0].arguments.contains("build"))
        XCTAssertEqual(invocations[1].arguments.prefix(3), ["simctl", "install", "SIM-1234"])
        XCTAssertEqual(invocations[2].arguments, ["simctl", "launch", "SIM-1234", "com.atjsh.GlassdeckDev"])
    }
}
