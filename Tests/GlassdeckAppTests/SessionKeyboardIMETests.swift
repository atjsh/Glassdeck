#if canImport(UIKit)
@testable import Glassdeck
import GlassdeckCore
import XCTest

@MainActor
final class SessionKeyboardIMETests: XCTestCase {

    func testSetMarkedTextThenUnmarkTextCommitsText() throws {
        let surface = try GhosttySurface()
        let outputCollector = OutputCollector()
        surface.setOutputHandler(outputCollector.handler)

        // Begin composing — should not produce committed output
        surface.setMarkedText("に")
        let outputAfterMark = outputCollector.data

        // Commit composing text
        surface.unmarkText()

        // The unmarkText should have committed "に" through the engine
        XCTAssertGreaterThan(
            outputCollector.data.count,
            outputAfterMark.count,
            "Committing marked text should produce terminal output"
        )
    }

    func testDeleteBackwardDuringPreeditDoesNotSendBackspaceToTerminal() throws {
        let surface = try GhosttySurface()
        let outputCollector = OutputCollector()
        surface.setOutputHandler(outputCollector.handler)

        // Begin composing
        surface.setMarkedText("に")
        let outputBeforeDelete = outputCollector.data

        // Delete during preedit should clear the preedit without sending backspace
        surface.deleteBackward()

        // deleteBackward during preedit should not produce additional terminal output
        XCTAssertEqual(
            outputCollector.data,
            outputBeforeDelete,
            "deleteBackward during preedit should not send backspace to terminal"
        )
    }
}

/// Thread-safe output collector for capturing GhosttySurface terminal output.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }

    var handler: @Sendable (Data) -> Void {
        { [weak self] chunk in
            guard let self else { return }
            self.lock.lock()
            self._data.append(chunk)
            self.lock.unlock()
        }
    }
}
#endif
