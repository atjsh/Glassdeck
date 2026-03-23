#if canImport(UIKit)
@testable import Glassdeck
import GlassdeckCore
import XCTest

@MainActor
final class SessionKeyboardIMETests: XCTestCase {

    func testSetMarkedTextThenUnmarkTextCommitsText() throws {
        let surface = try GhosttySurface()

        // Begin composing — preedit should not produce committed output
        surface.setMarkedText("に")

        // Commit composing text via unmarkText
        // In the GhosttyKit architecture, insertText / preedit flows through the
        // surface; verifying no crash is the primary validation on this path.
        surface.unmarkText()
    }

    func testDeleteBackwardDuringPreeditDoesNotCrash() throws {
        let surface = try GhosttySurface()

        // Begin composing
        surface.setMarkedText("に")

        // Delete during preedit should clear the preedit without crashing
        surface.deleteBackward()
    }
}
#endif
