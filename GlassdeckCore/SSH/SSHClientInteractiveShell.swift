import Foundation
import SSHClient

final class SSHClientInteractiveShell: InteractiveShell {
    let output: AsyncThrowingStream<Data, Error>

    private let shell: SSHShell

    init(shell: SSHShell) {
        self.shell = shell
        self.output = AsyncThrowingStream { continuation in
            shell.readHandler = { data in
                continuation.yield(data)
            }
            shell.closeHandler = { error in
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    func write(_ data: Data) async throws {
        try await shell.write(data)
    }

    func resize(
        to size: TerminalSize,
        pixelSize: TerminalPixelSize?
    ) async throws {
        try await shell.resize(
            to: SSHWindowSize(
                terminalCharacterWidth: size.columns,
                terminalRowHeight: size.rows,
                terminalPixelWidth: pixelSize?.width ?? 0,
                terminalPixelHeight: pixelSize?.height ?? 0
            )
        )
    }

    func close() async {
        try? await shell.close()
    }
}
