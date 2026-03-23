import Foundation
@testable import GlassdeckCore
import XCTest

/// End-to-end pipeline tests verifying the full GhosttyKit data path
/// (SSH ↔ Terminal) works correctly using mock objects.
final class GhosttyKitPipelineTests: XCTestCase {

    // MARK: - 1. SSH output → bridge → terminal

    func testSSHOutputReachesTerminal() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        let payload = Data("hello, terminal!".utf8)
        await shell.emitOutput(payload)
        try await Task.sleep(nanoseconds: 50_000_000)

        let rendered = await terminal.renderedOutput
        XCTAssertEqual(rendered, [payload])

        await bridge.stop()
    }

    // MARK: - 2. Terminal input → bridge → shell

    func testTerminalInputReachesShell() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        let input = Data("ls -la\n".utf8)
        await terminal.emitInput(input)
        try await Task.sleep(nanoseconds: 50_000_000)

        let writes = await shell.writes
        XCTAssertEqual(writes, [input])

        await bridge.stop()
    }

    // MARK: - 3. Bidirectional data flow in a single session

    func testBidirectionalDataFlow() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        // Shell → Terminal
        let shellPayload = Data("prompt$ ".utf8)
        await shell.emitOutput(shellPayload)
        try await Task.sleep(nanoseconds: 50_000_000)

        let rendered = await terminal.renderedOutput
        XCTAssertEqual(rendered, [shellPayload])

        // Terminal → Shell
        let userInput = Data("pwd\n".utf8)
        await terminal.emitInput(userInput)
        try await Task.sleep(nanoseconds: 50_000_000)

        let writes = await shell.writes
        XCTAssertEqual(writes, [userInput])

        await bridge.stop()
    }

    // MARK: - 4. Large data passes without corruption

    func testLargeDataChunking() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        // 64 KB of deterministic data
        var largeData = Data(count: 65_536)
        for i in largeData.indices {
            largeData[i] = UInt8(i % 256)
        }

        await shell.emitOutput(largeData)
        try await Task.sleep(nanoseconds: 200_000_000)

        let rendered = await terminal.renderedOutput
        let combined = rendered.reduce(Data(), +)
        XCTAssertEqual(combined, largeData, "64 KB payload should arrive intact")

        await bridge.stop()
    }

    // MARK: - 5. Rapid bidirectional traffic

    func testRapidBidirectionalTraffic() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        let messageCount = 100

        // Fire 100 messages from shell → terminal
        for i in 0..<messageCount {
            await shell.emitOutput(Data("out-\(i)\n".utf8))
        }

        // Fire 100 messages from terminal → shell
        for i in 0..<messageCount {
            await terminal.emitInput(Data("in-\(i)\n".utf8))
        }

        // Allow all async deliveries to settle
        try await Task.sleep(nanoseconds: 500_000_000)

        let rendered = await terminal.renderedOutput
        XCTAssertEqual(
            rendered.count, messageCount,
            "Terminal should have received all \(messageCount) shell messages"
        )

        let writes = await shell.writes
        XCTAssertEqual(
            writes.count, messageCount,
            "Shell should have received all \(messageCount) terminal messages"
        )

        // Verify ordering is preserved
        for i in 0..<messageCount {
            XCTAssertEqual(rendered[i], Data("out-\(i)\n".utf8))
            XCTAssertEqual(writes[i], Data("in-\(i)\n".utf8))
        }

        await bridge.stop()
    }

    // MARK: - 6. Stop cleans up handlers and halts data flow

    func testBridgeStopCleansUpHandlers() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        // Verify data flows before stop
        await shell.emitOutput(Data("before".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let beforeOutput = await terminal.renderedOutput
        XCTAssertEqual(beforeOutput, [Data("before".utf8)])

        await bridge.stop()

        // Output handler should be cleared
        let hasHandler = await terminal.hasOutputHandler
        XCTAssertFalse(hasHandler, "Terminal output handler should be nil after stop")

        // Create a new shell to verify no further data reaches terminal
        let shell2 = MockShell()
        // Manually write data; since bridge is stopped, nothing should forward
        await terminal.emitInput(Data("after-stop".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)

        // Terminal should still only have the data from before stop
        let afterOutput = await terminal.renderedOutput
        XCTAssertEqual(afterOutput.count, 1, "No new data should reach terminal after stop")

        _ = shell2 // suppress unused warning
    }

    // MARK: - 7. Resize propagates from bridge to shell

    func testResizePropagatesFromTerminalToShell() async throws {
        let terminal = MockTerminal()
        let shell = MockShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        await bridge.resize(columns: 120, rows: 40)

        let resizes = await shell.resizes
        XCTAssertEqual(resizes.count, 1)
        XCTAssertEqual(resizes.first?.0, TerminalSize(columns: 120, rows: 40))

        await bridge.stop()
    }
}

// MARK: - Mock Types

/// A mock TerminalIO that records writes and lets tests inject input.
private actor MockTerminal: TerminalIO {
    private var outputHandler: (@Sendable (Data) -> Void)?
    private(set) var renderedOutput: [Data] = []

    var hasOutputHandler: Bool {
        outputHandler != nil
    }

    func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) async {
        outputHandler = handler
    }

    func write(_ data: Data) async {
        renderedOutput.append(data)
    }

    /// Simulates the terminal producing user input.
    func emitInput(_ data: Data) {
        outputHandler?(data)
    }
}

/// A mock InteractiveShell backed by an AsyncThrowingStream.
private actor MockShell: InteractiveShell {
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private(set) var writes: [Data] = []
    private(set) var resizes: [(TerminalSize, TerminalPixelSize?)] = []

    nonisolated let output: AsyncThrowingStream<Data, Error>

    init() {
        var localContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        self.output = AsyncThrowingStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }

    func write(_ data: Data) async throws {
        writes.append(data)
    }

    func resize(to size: TerminalSize, pixelSize: TerminalPixelSize?) async throws {
        resizes.append((size, pixelSize))
    }

    func close() async {
        continuation?.finish()
    }

    func emitOutput(_ data: Data) {
        continuation?.yield(data)
    }
}
