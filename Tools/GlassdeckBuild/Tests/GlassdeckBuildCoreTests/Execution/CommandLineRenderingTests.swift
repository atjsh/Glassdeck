import XCTest
@testable import GlassdeckBuildCore

final class CommandLineRenderingTests: XCTestCase {
    func testSimpleRender() {
        let invocation = ProcessInvocation(
            executable: "/usr/bin/env",
            arguments: ["xcodebuild", "-scheme", "Glassdeck"]
        )
        XCTAssertEqual(
            CommandLineRendering.render(invocation),
            "/usr/bin/env xcodebuild -scheme Glassdeck"
        )
    }

    func testRenderWithQuoting() {
        let invocation = ProcessInvocation(
            executable: "/usr/bin/env",
            arguments: ["echo", "hello world", "quoted\"text\""]
        )
        XCTAssertEqual(
            CommandLineRendering.render(invocation),
            "/usr/bin/env echo 'hello world' 'quoted\"text\"'"
        )
    }
}
