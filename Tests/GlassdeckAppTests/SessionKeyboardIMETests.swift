@testable import Glassdeck
import GlassdeckCore
import XCTest

@MainActor
final class SessionKeyboardIMETests: XCTestCase {
    func testKeyboardHostForwardsTypedCharactersExactlyOnce() {
        let host = SessionKeyboardHostView()
        let recorder = KeyboardInputRecorder()
        host.update(surface: nil, inputSink: recorder, isFocused: false, softwareKeyboardPresented: true)

        host.insertText("pwd")

        XCTAssertEqual(recorder.insertedTexts, ["pwd"])
        XCTAssertEqual(recorder.deleteCount, 0)
    }

    func testKeyboardHostForwardsNewlineThroughEventPath() {
        let host = SessionKeyboardHostView()
        let recorder = KeyboardInputRecorder()
        host.update(surface: nil, inputSink: recorder, isFocused: false, softwareKeyboardPresented: true)

        host.insertText("\n")

        XCTAssertEqual(recorder.insertedTexts, ["\n"])
        XCTAssertEqual(recorder.deleteCount, 0)
    }

    func testKeyboardHostForwardsDeleteBackwardThroughEventPath() {
        let host = SessionKeyboardHostView()
        let recorder = KeyboardInputRecorder()
        host.update(surface: nil, inputSink: recorder, isFocused: false, softwareKeyboardPresented: true)
        host.insertText("x")
        recorder.reset()

        host.deleteBackward()

        XCTAssertEqual(recorder.insertedTexts, [])
        XCTAssertEqual(recorder.deleteCount, 1)
    }

    func testKeyboardHostFallbackReplacementDoesNotDuplicateForwardedInput() {
        let host = SessionKeyboardHostView()
        let recorder = KeyboardInputRecorder()
        host.update(surface: nil, inputSink: recorder, isFocused: false, softwareKeyboardPresented: true)
        host.insertText("pwd")
        recorder.reset()

        host.text = "pwd!"
        host.sendActions(for: .editingChanged)

        XCTAssertEqual(recorder.insertedTexts, ["!"])
        XCTAssertEqual(recorder.deleteCount, 0)
    }

    func testKeyboardHostTextDidChangeNotificationFallbackForwardsTextDeltaOnce() {
        let host = SessionKeyboardHostView()
        let recorder = KeyboardInputRecorder()
        host.update(surface: nil, inputSink: recorder, isFocused: false, softwareKeyboardPresented: true)
        host.insertText("pwd")
        recorder.reset()

        host.text = "pwd!"
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: host)

        XCTAssertEqual(recorder.insertedTexts, ["!"])
        XCTAssertEqual(recorder.deleteCount, 0)
    }

    func testKeyboardHostSyntheticSurfaceEventPathReachesBridgeShell() async throws {
        let surface = try GhosttySurface()
        let host = SessionKeyboardHostView()
        let shell = RecordingInteractiveShell()
        let bridge = SSHPTYBridge(terminal: GhosttySurfaceTerminalIO(surface: surface))

        await bridge.start(shell: shell)
        defer {
            Task {
                await bridge.stop()
            }
        }

        host.update(surface: surface, inputSink: surface, isFocused: false, softwareKeyboardPresented: true)

        host.insertText("echo GLASSDECK")
        host.insertText("\n")

        try await Task.sleep(for: .milliseconds(100))

        let writes = await shell.writes
        let combinedWrites = writes.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(combinedWrites, Data("echo GLASSDECK\n".utf8))
    }

    func testKeyboardHostSyntheticSurfaceFallbackReplacementReachesBridgeShell() async throws {
        let surface = try GhosttySurface()
        let host = SessionKeyboardHostView()
        let shell = RecordingInteractiveShell()
        let bridge = SSHPTYBridge(terminal: GhosttySurfaceTerminalIO(surface: surface))

        await bridge.start(shell: shell)
        defer {
            Task {
                await bridge.stop()
            }
        }

        host.update(surface: surface, inputSink: surface, isFocused: false, softwareKeyboardPresented: true)

        host.text = "pwd!"
        host.sendActions(for: .editingChanged)

        try await Task.sleep(for: .milliseconds(100))

        let writes = await shell.writes
        let combinedWrites = writes.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(combinedWrites, Data("pwd!".utf8))
    }

    func testKeyboardHostSyntheticSurfaceReplaceTextPreservesNewlineToBridgeShell() async throws {
        let surface = try GhosttySurface()
        let host = SessionKeyboardHostView()
        let shell = RecordingInteractiveShell()
        let bridge = SSHPTYBridge(terminal: GhosttySurfaceTerminalIO(surface: surface))

        await bridge.start(shell: shell)
        defer {
            Task {
                await bridge.stop()
            }
        }

        host.update(surface: surface, inputSink: surface, isFocused: false, softwareKeyboardPresented: true)

        let insertionRange = try XCTUnwrap(host.textRange(from: host.beginningOfDocument, to: host.beginningOfDocument))
        host.replace(insertionRange, withText: "pwd\n")

        try await Task.sleep(for: .milliseconds(100))

        let writes = await shell.writes
        let combinedWrites = writes.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(combinedWrites, Data("pwd\n".utf8))
    }

    func testSetMarkedTextThenUnmarkTextCommitsText() throws {
        throw XCTSkip(
            "IME preedit smoke coverage remains in the UI and integration harnesses; " +
            "the unit-test host still crashes intermittently when a surface-owning Ghostty view tears down."
        )
    }

    func testDeleteBackwardDuringPreeditDoesNotCrash() throws {
        throw XCTSkip(
            "IME preedit smoke coverage remains in the UI and integration harnesses; " +
            "the unit-test host still crashes intermittently when a surface-owning Ghostty view tears down."
        )
    }
}

@MainActor
private final class KeyboardInputRecorder: SessionKeyboardInputSink {
    private(set) var insertedTexts: [String] = []
    private(set) var deleteCount = 0

    func insertText(_ text: String) {
        insertedTexts.append(text)
    }

    func deleteBackward() {
        deleteCount += 1
    }

    func reset() {
        insertedTexts.removeAll()
        deleteCount = 0
    }
}

private actor RecordingInteractiveShell: InteractiveShell {
    private(set) var writes: [Data] = []

    nonisolated let output = AsyncThrowingStream<Data, Error> { _ in }

    func write(_ data: Data) async throws {
        writes.append(data)
    }

    func resize(to size: TerminalSize, pixelSize: TerminalPixelSize?) async throws {}

    func close() async {}
}
