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

/// SwiftUI terminal surface that renders a GhosttySurface.
///
/// Wraps the GhosttySurface UIView via UIViewRepresentable.
/// The surface is owned by the SessionManager and passed in.
struct TerminalSurfaceView: View {
    let session: SSHSessionModel
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        ZStack {
            // GhosttyKit terminal rendering surface
            if let surface = sessionManager.surface(for: session.id) {
                GhosttyTerminalViewWrapper(surface: surface)
                    .ignoresSafeArea()
            } else {
                // Fallback when no surface is available (loading/error state)
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    statusIcon
                    statusText
                }
            }

            // Connection status overlay (when not connected)
            if !session.isConnected {
                statusOverlay
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .connecting, .authenticating, .reconnecting:
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
        case .disconnected:
            Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        Text(session.status.label)
            .font(.body.monospaced())
            .foregroundStyle(.white.opacity(0.7))
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: session.status.systemImage)
                Text(session.status.label)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 60)
        }
    }
}

/// UIViewRepresentable wrapper for an existing GhosttySurface.
///
/// Unlike GhosttyTerminalView which creates a new surface,
/// this wraps a surface owned by SessionManager.
struct GhosttyTerminalViewWrapper: UIViewRepresentable {
    let surface: GhosttySurface

    func makeUIView(context: Context) -> GhosttySurface {
        surface.setFocused(true)
        return surface
    }

    func updateUIView(_ uiView: GhosttySurface, context: Context) {
        // Surface state is managed externally by PTYBridge
    }
}
