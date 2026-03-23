import XCTest
@testable import GlassdeckBuildCore

final class SimulatorClipboardTests: XCTestCase {
    func testFileCopyInvocationUsesSimulatorIdentifier() {
        let clipboard = SimulatorClipboard()
        let invocation = clipboard.copyFileInvocation(
            simulatorIdentifier: "SIM123",
            fileURL: URL(fileURLWithPath: "/tmp/test key")
        )

        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments.first, "-lc")
        XCTAssertEqual(invocation.arguments[1].contains("SIM123"), true)
        XCTAssertEqual(invocation.arguments[1].contains("/tmp/test key"), true)
    }

    func testTextCopyInvocationEscapesText() {
        let clipboard = SimulatorClipboard()
        let invocation = clipboard.copyTextInvocation(simulatorIdentifier: "SIM123", text: "hello world")
        XCTAssertEqual(invocation.arguments[1].contains("hello world"), true)
        XCTAssertEqual(invocation.arguments[1].contains("printf %s"), true)
    }
}
