import SwiftUI

/// Protocol abstracting the terminal rendering engine.
/// Allows swapping between GhosttyKit and SwiftTerm backends.
protocol TerminalEngine: Sendable {
    /// Write data received from SSH channel into the terminal
    func write(_ data: Data) async
    /// Read user input from the terminal to send to SSH channel
    func onInput(_ handler: @escaping @Sendable (Data) -> Void)
    /// Resize the terminal to the given dimensions
    func resize(columns: Int, rows: Int) async
    /// Current terminal dimensions
    var terminalSize: TerminalSize { get async }
}

struct TerminalSize: Sendable, Equatable {
    let columns: Int
    let rows: Int
}

/// Placeholder terminal surface view.
/// Will be replaced with GhosttyKit UIViewRepresentable wrapper.
struct TerminalSurfaceView: View {
    let session: SSHSessionModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            Text("Terminal: \(session.displayName)")
                .font(.body.monospaced())
                .foregroundStyle(.green)
        }
    }
}
