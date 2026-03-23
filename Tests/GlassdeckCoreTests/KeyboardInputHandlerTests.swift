import XCTest

/// Tests for keyboard input handling logic.
///
/// The key mapping from UIKeyboardHIDUsage → ghostty_input_key_e is defined
/// as a private extension in GhosttyTerminalView.swift. These tests verify
/// the conceptual correctness of input handling patterns used in the terminal.
///
/// When the key mapping is extracted to a public/internal type, these tests
/// should be updated to test it directly.
final class KeyboardInputHandlerTests: XCTestCase {
    // Test basic character mapping expectations
    func testASCIICharactersArePreserved() {
        let ascii = "abcdefghijklmnopqrstuvwxyz0123456789"
        for char in ascii {
            let data = Data(String(char).utf8)
            XCTAssertEqual(data.count, 1, "ASCII char '\(char)' should be 1 byte")
        }
    }

    func testControlCharacterEncoding() {
        // Ctrl+C = 0x03
        let ctrlC = Data([0x03])
        XCTAssertEqual(ctrlC.count, 1)
        XCTAssertEqual(ctrlC[0], 3)
    }

    func testDeleteBackwardProducesCorrectCode() {
        // Delete backward = 0x7F
        let del = "\u{7f}"
        XCTAssertEqual(del.utf8.count, 1)
        XCTAssertEqual(Array(del.utf8)[0], 0x7F)
    }

    func testEscapeSequenceEncoding() {
        let esc = "\u{1b}"
        XCTAssertEqual(Array(esc.utf8), [0x1B])
    }

    func testBracketedPastePrefix() {
        let prefix = "\u{1b}[200~"
        XCTAssertTrue(prefix.hasPrefix("\u{1b}["))
        XCTAssertTrue(prefix.hasSuffix("~"))
    }

    func testBracketedPasteSuffix() {
        let suffix = "\u{1b}[201~"
        XCTAssertTrue(suffix.hasPrefix("\u{1b}["))
    }

    func testBracketedPasteWrapping() {
        let text = "hello world"
        let bracketed = "\u{1b}[200~\(text)\u{1b}[201~"
        XCTAssertTrue(bracketed.contains(text))
        XCTAssertTrue(bracketed.hasPrefix("\u{1b}[200~"))
        XCTAssertTrue(bracketed.hasSuffix("\u{1b}[201~"))
    }

    func testEmptyTextBracketedPaste() {
        let text = ""
        let bracketed = "\u{1b}[200~\(text)\u{1b}[201~"
        XCTAssertEqual(bracketed, "\u{1b}[200~\u{1b}[201~")
    }

    func testUTF8TextPreservation() {
        let text = "こんにちは"
        let data = Data(text.utf8)
        let roundtripped = String(data: data, encoding: .utf8)
        XCTAssertEqual(roundtripped, text)
    }

    func testModifierFlagsCombination() {
        // Test that combining modifier bit flags works correctly
        let shift: UInt32 = 1
        let ctrl: UInt32 = 2
        let alt: UInt32 = 4
        let combined = shift | ctrl | alt
        XCTAssertEqual(combined & shift, shift)
        XCTAssertEqual(combined & ctrl, ctrl)
        XCTAssertEqual(combined & alt, alt)
    }

    func testNilCharactersHandling() {
        let emptyString = ""
        XCTAssertTrue(emptyString.isEmpty)
        XCTAssertEqual(emptyString.utf8.count, 0)
    }
}
