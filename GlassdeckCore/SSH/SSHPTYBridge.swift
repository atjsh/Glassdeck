import Foundation

/// Bridges an interactive shell session to a terminal engine.
///
/// Pipes shell output into the terminal and terminal-produced input back into
/// the remote shell. The bridge is UI-agnostic and can be exercised entirely
/// with test doubles.
public actor SSHPTYBridge {
    private var terminal: any TerminalIO
    private var shell: (any InteractiveShell)?
    private var isActive = false
    private var readTask: Task<Void, Never>?
    private var currentSize = TerminalSize(columns: 80, rows: 24)
    private var onDisconnect: (@Sendable () -> Void)?
    private var terminalOutputHandler: (@Sendable (Data) -> Void)?

    public init(terminal: any TerminalIO) {
        self.terminal = terminal
    }

    public func start(shell: any InteractiveShell) async {
        self.shell = shell
        isActive = true

        let outputHandler: @Sendable (Data) -> Void = { [weak self] data in
            guard let self else { return }
            Task { await self.sendToShell(data) }
        }
        terminalOutputHandler = outputHandler
        await terminal.setOutputHandler(outputHandler)

        readTask = Task { [weak self] in
            guard let self else { return }

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

    private func sendToShell(_ data: Data) async {
        guard isActive, let shell else { return }

        do {
            try await shell.write(data)
        } catch {
            await handleDisconnect()
        }
    }

    private func handleDisconnect() async {
        guard isActive else { return }
        isActive = false
        terminalOutputHandler = nil
        await terminal.setOutputHandler(nil)
        onDisconnect?()
    }
}
