import XCTest
@testable import GlassdeckBuildCore

final class ProcessRunnerTests: XCTestCase {
    func testDefaultProcessRunnerCapturesLargeOutputWithoutDeadlock() async throws {
        let runner = DefaultProcessRunner()
        let result = try await runner.run(
            ProcessInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    "-c",
                    "import sys; sys.stdout.write('o' * 200000); sys.stderr.write('e' * 150000)",
                ]
            )
        )

        XCTAssertEqual(result.standardOutput.count, 200000)
        XCTAssertEqual(result.standardError.count, 150000)
    }
}
