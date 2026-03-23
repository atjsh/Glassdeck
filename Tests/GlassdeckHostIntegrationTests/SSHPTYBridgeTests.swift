import Foundation
@testable import GlassdeckCore
import XCTest

final class SSHPTYBridgeTests: XCTestCase {
    func testBridgeForwardsShellOutputInputAndResize() async throws {
        let terminal = FakeTerminal()
        let shell = FakeShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell)

        await shell.emitOutput(Data("hello".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let renderedOutput = await terminal.renderedOutput
        XCTAssertEqual(renderedOutput, [Data("hello".utf8)])

        await terminal.emitInput(Data("ls\n".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let writes = await shell.writes
        XCTAssertEqual(writes, [Data("ls\n".utf8)])

        await bridge.resize(
            columns: 132,
            rows: 43,
            pixelSize: TerminalPixelSize(width: 1200, height: 900)
        )
        let resizes = await shell.resizes
        XCTAssertEqual(resizes.count, 1)
        XCTAssertEqual(resizes.first?.0, TerminalSize(columns: 132, rows: 43))
        XCTAssertEqual(resizes.first?.1, TerminalPixelSize(width: 1200, height: 900))

        await bridge.stop()
    }

    func testBridgeInvokesDisconnectHandlerOnShellFailure() async throws {
        let terminal = FakeTerminal()
        let shell = FakeShell()
        let bridge = SSHPTYBridge(terminal: terminal)
        let disconnects = DisconnectRecorder()

        await bridge.setOnDisconnect {
            Task { await disconnects.record() }
        }
        await bridge.start(shell: shell)

        await shell.failOutput(TestError.disconnected)
        try await Task.sleep(nanoseconds: 50_000_000)

        let disconnectCount = await disconnects.count
        XCTAssertEqual(disconnectCount, 1)

        await terminal.emitInput(Data("pwd\n".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let writes = await shell.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testReconnectAfterDisconnect() async throws {
        let terminal = FakeTerminal()
        let shell1 = FakeShell()
        let shell2 = FakeShell()
        let bridge = SSHPTYBridge(terminal: terminal)

        await bridge.start(shell: shell1)
        await bridge.stop()
        await bridge.start(shell: shell2)

        // Bridge should be functional with new shell
        await shell2.emitOutput(Data("reconnected".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let output = await terminal.renderedOutput
        XCTAssertEqual(output.last, Data("reconnected".utf8))
    }

    func testWriteFailureTriggersDisconnect() async throws {
        let terminal = FakeTerminal()
        let bridge = SSHPTYBridge(terminal: terminal)
        let shell = FakeShell()
        await shell.setFailWrites(true)

        let disconnects = DisconnectRecorder()
        await bridge.setOnDisconnect {
            Task { await disconnects.record() }
        }

        await bridge.start(shell: shell)

        // Simulate terminal sending data to shell (which will fail)
        await terminal.emitInput(Data("test".utf8))
        try await Task.sleep(nanoseconds: 100_000_000)

        let disconnectCount = await disconnects.count
        XCTAssertEqual(disconnectCount, 1)
    }

    func testRapidResizeCoalescing() async throws {
        let terminal = FakeTerminal()
        let bridge = SSHPTYBridge(terminal: terminal)
        let shell = FakeShell()

        await bridge.start(shell: shell)

        // Send multiple rapid resizes
        for cols in 80...85 {
            await bridge.resize(columns: cols, rows: 24)
        }

        // All resizes should have been processed without crash
        let resizes = await shell.resizes
        XCTAssertFalse(resizes.isEmpty, "At least some resizes should be forwarded")
    }

    func testTerminalReplacementClearsOldHandler() async throws {
        let terminal1 = FakeTerminal()
        let terminal2 = FakeTerminal()
        let bridge = SSHPTYBridge(terminal: terminal1)
        let shell = FakeShell()

        await bridge.start(shell: shell)
        await bridge.replaceTerminal(terminal2)

        // Old terminal's handler should be cleared
        let handler1Active = await terminal1.hasOutputHandler
        XCTAssertFalse(handler1Active, "Old terminal should have its handler cleared")

        // New terminal should have an active handler
        let handler2Active = await terminal2.hasOutputHandler
        XCTAssertTrue(handler2Active, "New terminal should have a handler set")
    }

    func testBridgeCanReplaceTerminalWithoutDisconnectingShell() async throws {
        let initialTerminal = FakeTerminal()
        let replacementTerminal = FakeTerminal()
        let shell = FakeShell()
        let bridge = SSHPTYBridge(terminal: initialTerminal)

        await bridge.start(shell: shell)

        await shell.emitOutput(Data("before".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let initialRenderedOutputBeforeReplace = await initialTerminal.renderedOutput
        XCTAssertEqual(initialRenderedOutputBeforeReplace, [Data("before".utf8)])

        await bridge.replaceTerminal(replacementTerminal)
        await shell.emitOutput(Data("after".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)

        let initialRenderedOutputAfterReplace = await initialTerminal.renderedOutput
        let replacementRenderedOutput = await replacementTerminal.renderedOutput
        XCTAssertEqual(initialRenderedOutputAfterReplace, [Data("before".utf8)])
        XCTAssertEqual(replacementRenderedOutput, [Data("after".utf8)])

        await replacementTerminal.emitInput(Data("pwd\n".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let writesAfterReplacementInput = await shell.writes
        XCTAssertEqual(writesAfterReplacementInput, [Data("pwd\n".utf8)])

        await initialTerminal.emitInput(Data("ignored\n".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        let writesAfterOldTerminalInput = await shell.writes
        XCTAssertEqual(writesAfterOldTerminalInput, [Data("pwd\n".utf8)])
    }
}

private actor FakeTerminal: TerminalIO {
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

    func emitInput(_ data: Data) {
        outputHandler?(data)
    }
}

private actor FakeShell: InteractiveShell {
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

    private var failWrites = false

    func setFailWrites(_ value: Bool) {
        failWrites = value
    }

    func write(_ data: Data) async throws {
        if failWrites { throw TestError.disconnected }
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

    func failOutput(_ error: Error) {
        continuation?.finish(throwing: error)
    }
}

private actor DisconnectRecorder {
    private var disconnects = 0

    func record() {
        disconnects += 1
    }

    var count: Int {
        disconnects
    }
}

private enum TestError: Error {
    case disconnected
}
