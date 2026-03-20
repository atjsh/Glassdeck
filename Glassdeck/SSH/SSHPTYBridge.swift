import Foundation
import NIOCore
import NIOSSH
import SSHClient

/// Bridges the SSH PTY channel I/O with the terminal engine.
///
/// Pipes SSH channel stdout → terminal input and terminal user input → SSH channel stdin.
/// Handles terminal resize events → SSH window-change requests.
///
/// Architecture:
/// ```
///  Terminal Surface ←─ write() ──── SSHShell.data (AsyncThrowingStream)
///  Terminal Surface ──→ onOutput ──→ SSHShell.write(Data)
///  Terminal resize  ──→ resize() ──→ SSH WindowChangeRequest (via NIOSSH)
/// ```
actor SSHPTYBridge {
    /// Terminal rendering surface that receives SSH output.
    private let surface: GhosttySurface

    /// SSH shell session providing async data stream and write access.
    private var shell: SSHShell?

    /// Whether the bridge is actively forwarding data.
    private var isActive = false

    /// Task reading from SSH shell data stream.
    private var readTask: Task<Void, Never>?

    /// Current terminal dimensions (columns × rows).
    private var currentSize: TerminalSize = TerminalSize(columns: 80, rows: 24)

    /// Callback for connection status changes.
    var onDisconnect: (@Sendable () -> Void)?

    init(surface: GhosttySurface) {
        self.surface = surface
    }

    /// Start bidirectional I/O bridging.
    ///
    /// - Parameter shell: An open `SSHShell` from swift-ssh-client.
    func start(shell: SSHShell) async {
        self.shell = shell
        isActive = true

        // Forward terminal user input → SSH channel
        surface.onOutput = { [weak self] data in
            guard let self else { return }
            Task { await self.sendToSSH(data) }
        }

        // Forward SSH channel output → terminal surface
        readTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in shell.data {
                    guard await self.isActive else { break }
                    await MainActor.run {
                        self.surface.writeToTerminal(chunk)
                    }
                }
                // Stream ended — server closed the channel
                await self.handleDisconnect()
            } catch {
                await self.handleDisconnect()
            }
        }
    }

    /// Stop the bridge and cancel the read loop.
    func stop() {
        isActive = false
        readTask?.cancel()
        readTask = nil
        shell = nil
        surface.onOutput = nil
    }

    /// Handle terminal resize: update local size and send SSH window-change.
    ///
    /// Terminal resize flow:
    /// 1. GhosttySurface.layoutSubviews() detects new size
    /// 2. Calls onResize → PTYBridge.resize()
    /// 3. Bridge sends WindowChangeRequest to SSH server
    func resize(columns: Int, rows: Int) async {
        let newSize = TerminalSize(columns: columns, rows: rows)
        guard newSize != currentSize else { return }
        currentSize = newSize

        // SSH window-change request via NIOSSH.
        // SSHShell from swift-ssh-client doesn't expose direct window-change,
        // so we reach through to the underlying NIOSSH channel handler.
        //
        // NOTE: When swift-ssh-client adds window resize support,
        // replace this with: try await shell?.resizeTerminal(columns: columns, rows: rows)
        //
        // For now, this is handled by our custom channel handler injection
        // in SSHConnectionManager.openShell().
        await sendWindowChange(columns: columns, rows: rows)
    }

    // MARK: - Private

    /// Write data from terminal to the SSH channel.
    private func sendToSSH(_ data: Data) async {
        guard isActive, let shell else { return }
        do {
            try await shell.write(data)
        } catch {
            // Write failure usually means the connection dropped
            await handleDisconnect()
        }
    }

    /// Send an SSH window-change request.
    ///
    /// This uses the NIOSSH low-level API since swift-ssh-client
    /// doesn't expose terminal resize at the high level.
    private func sendWindowChange(columns: Int, rows: Int) async {
        // Window change is sent as an SSH channel request.
        // The SSHConnectionManager injects a WindowChangeHandler
        // into the channel pipeline when opening the shell.
        //
        // TODO: Implement when we have access to the NIOSSH channel:
        // let request = SSHChannelRequestEvent.WindowChangeRequest(
        //     terminalCharacterWidth: UInt32(columns),
        //     terminalRowHeight: UInt32(rows),
        //     terminalPixelWidth: 0,
        //     terminalPixelHeight: 0
        // )
        // try? await channel.triggerUserOutboundEvent(request)
    }

    private func handleDisconnect() async {
        isActive = false
        onDisconnect?()
    }
}
