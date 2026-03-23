import Foundation
import os

/// Bridges an interactive shell session to a terminal engine.
///
/// Pipes shell output into the terminal and terminal-produced input back into
/// the remote shell. The bridge is UI-agnostic and can be exercised entirely
/// with test doubles.
public actor SSHPTYBridge {
    private static let logger = Logger(subsystem: "com.glassdeck", category: "SSHPTYBridge")
    private static let shellWriteCoalesceInterval: Duration = .milliseconds(5)
    private static let debugTerminalInput = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private var terminal: any TerminalIO
    private var shell: (any InteractiveShell)?
    private var isActive = false
    private var readTask: Task<Void, Never>?
    private var currentSize = TerminalSize(columns: 80, rows: 24)
    private var onDisconnect: (@Sendable () -> Void)?
    private var terminalOutputHandler: (@Sendable (Data) -> Void)?
    private var pendingShellInput = Data()
    private var shellWriteTask: Task<Void, Never>?

    public init(terminal: any TerminalIO) {
        self.terminal = terminal
    }

    public func start(shell: any InteractiveShell) async {
        self.shell = shell
        isActive = true
        pendingShellInput.removeAll(keepingCapacity: false)
        shellWriteTask?.cancel()
        shellWriteTask = nil

        let outputHandler: @Sendable (Data) -> Void = { [weak self] data in
            guard let self else { return }
            Task { await self.enqueueShellInput(data) }
        }
        terminalOutputHandler = outputHandler
        await terminal.setOutputHandler(outputHandler)

        readTask = Task { [weak self] in
            guard let self else { return }
            guard let shell = await self.shell else { return }

            do {
                for try await chunk in shell.output {
                    guard await self.isActive else { break }
                    await self.terminal.write(chunk)
                }
            } catch {
                // The disconnect callback is the only externally
                // observable result we need from bridge failures.
            }

            await self.handleDisconnect()
        }
    }

    public func stop() async {
        isActive = false
        readTask?.cancel()
        readTask = nil
        clearPendingShellInput()

        if let shell {
            await shell.close()
        }

        self.shell = nil
        terminalOutputHandler = nil
        await terminal.setOutputHandler(nil)
    }

    public func setOnDisconnect(_ handler: @escaping @Sendable () -> Void) {
        onDisconnect = handler
    }

    public func replaceTerminal(_ terminal: any TerminalIO) async {
        let previousTerminal = self.terminal
        self.terminal = terminal

        await previousTerminal.setOutputHandler(nil)
        await terminal.setOutputHandler(isActive ? terminalOutputHandler : nil)
    }

    public func sendInput(_ data: Data) async {
        await enqueueShellInput(data)
    }

    public func resize(
        columns: Int,
        rows: Int,
        pixelSize: TerminalPixelSize? = nil
    ) async {
        let newSize = TerminalSize(columns: columns, rows: rows)
        guard newSize != currentSize else { return }
        currentSize = newSize

        do {
            try await shell?.resize(to: newSize, pixelSize: pixelSize)
        } catch {
            await handleDisconnect()
        }
    }

    private func enqueueShellInput(_ data: Data) async {
        guard isActive, !data.isEmpty else { return }
        debugLog("enqueue len=\(data.count) data=\(Self.debugDescription(for: data))")
        pendingShellInput.append(data)
        guard shellWriteTask == nil else { return }

        shellWriteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.shellWriteCoalesceInterval)
            guard !Task.isCancelled, let self else { return }
            await self.drainPendingShellInput()
        }
    }

    private func drainPendingShellInput() async {
        defer { shellWriteTask = nil }
        guard isActive, let shell else {
            pendingShellInput.removeAll(keepingCapacity: false)
            return
        }

        while isActive && !Task.isCancelled {
            let payload = pendingShellInput
            guard !payload.isEmpty else { return }
            pendingShellInput.removeAll(keepingCapacity: true)
            debugLog("drain len=\(payload.count) data=\(Self.debugDescription(for: payload))")

            do {
                try await shell.write(payload)
            } catch {
                pendingShellInput.removeAll(keepingCapacity: false)
                await handleDisconnect()
                return
            }
        }
    }

    private func clearPendingShellInput() {
        pendingShellInput.removeAll(keepingCapacity: false)
        shellWriteTask?.cancel()
        shellWriteTask = nil
    }

    private func handleDisconnect() async {
        guard isActive else { return }
        isActive = false
        clearPendingShellInput()
        terminalOutputHandler = nil
        await terminal.setOutputHandler(nil)
        onDisconnect?()
    }

    private func debugLog(_ message: String) {
        guard Self.debugTerminalInput else { return }
        NSLog("SSHPTYBridge %@", message)
    }

    private static func debugDescription(for data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
