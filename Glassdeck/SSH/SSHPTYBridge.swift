import Foundation

/// Bridges the SSH PTY channel I/O with the terminal engine.
///
/// Pipes SSH channel stdout → terminal input and terminal user input → SSH channel stdin.
/// Handles terminal resize events → SSH window-change requests.
actor SSHPTYBridge {
    private let terminalEngine: any TerminalEngine
    private var isActive = false

    init(terminalEngine: any TerminalEngine) {
        self.terminalEngine = terminalEngine
    }

    /// Start bridging between SSH channel and terminal.
    func start() async {
        isActive = true

        // Forward user input from terminal to SSH channel
        terminalEngine.onInput { [weak self] data in
            Task {
                await self?.sendToSSH(data)
            }
        }

        // TODO: Start reading from SSH channel and forwarding to terminal
        // while isActive {
        //     let data = try await sshChannel.read()
        //     await terminalEngine.write(data)
        // }
    }

    /// Stop the bridge.
    func stop() {
        isActive = false
    }

    /// Send data from terminal to SSH channel.
    private func sendToSSH(_ data: Data) {
        guard isActive else { return }
        // TODO: Write data to SSH PTY channel
    }

    /// Handle terminal resize.
    func resize(columns: Int, rows: Int) async {
        await terminalEngine.resize(columns: columns, rows: rows)
        // TODO: Send SSH window-change request
        // channel.sendWindowChange(columns: columns, rows: rows)
    }
}
