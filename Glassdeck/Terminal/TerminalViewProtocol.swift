#if canImport(UIKit)
import GlassdeckCore
import SwiftUI

/// Protocol abstracting the terminal rendering engine.
/// The current concrete implementation is the Ghostty VT surface.
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

/// SwiftUI terminal surface that renders the session-owned Ghostty VT surface.
struct TerminalSurfaceView: View {
    let session: SSHSessionModel

    private var exposesUITestInputProxy: Bool {
        UITestLaunchSupport.exposesTerminalRenderSummary
    }

    var body: some View {
        let connectedSurfaceInvariantBroken = session.isConnected && session.surface == nil
        let terminalRenderFailureReason = session.terminalRenderFailureReason
        let _ = Self.reportConnectedSurfaceInvariantViolation(
            for: session,
            isBroken: connectedSurfaceInvariantBroken
        )

        ZStack {
            if let surface = session.surface {
                GhosttyTerminalViewWrapper(
                    surface: surface,
                    isFocused: !exposesUITestInputProxy
                )
                    .ignoresSafeArea()

                if let terminalRenderFailureReason, session.isConnected {
                    terminalUnavailableOverlay(reason: terminalRenderFailureReason)
                }
            } else {
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    statusIcon(connectedSurfaceInvariantBroken: connectedSurfaceInvariantBroken)
                    statusText(connectedSurfaceInvariantBroken: connectedSurfaceInvariantBroken)
                }
            }

            if !session.isConnected || connectedSurfaceInvariantBroken {
                statusOverlay(connectedSurfaceInvariantBroken: connectedSurfaceInvariantBroken)
            }
        }
        .overlay {
            SessionKeyboardInputHost(
                session: session,
                isFocused: true,
                softwareKeyboardPresented: exposesUITestInputProxy
            )
            .frame(width: exposesUITestInputProxy ? 44 : 1, height: exposesUITestInputProxy ? 44 : 1)
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-surface-view")
    }

    @ViewBuilder
    private func statusIcon(connectedSurfaceInvariantBroken: Bool) -> some View {
        if connectedSurfaceInvariantBroken {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
        } else {
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
    }

    @ViewBuilder
    private func statusText(connectedSurfaceInvariantBroken: Bool) -> some View {
        VStack(spacing: 6) {
            Text(connectedSurfaceInvariantBroken ? "Terminal Unavailable" : session.status.label)
                .font(.body.monospaced())
                .foregroundStyle(.white.opacity(0.7))

            if connectedSurfaceInvariantBroken {
                Text("Connected session is missing a bound terminal surface.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private func terminalUnavailableOverlay(reason: String) -> some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Terminal Unavailable")
                    .font(.body.monospaced())
                    .foregroundStyle(.white.opacity(0.85))

                Text("Ghostty could not produce a render snapshot for this session.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text(reason)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func statusOverlay(connectedSurfaceInvariantBroken: Bool) -> some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: connectedSurfaceInvariantBroken ? "exclamationmark.triangle" : session.status.systemImage)
                Text(connectedSurfaceInvariantBroken ? "Terminal unavailable" : session.status.label)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 60)
        }
    }

    private static func reportConnectedSurfaceInvariantViolation(
        for session: SSHSessionModel,
        isBroken: Bool
    ) {
        guard isBroken else { return }
        assertionFailure("Connected session \(session.id) is missing its GhosttySurface.")
    }
}

/// UIViewRepresentable wrapper for an existing session-owned GhosttySurface.
struct GhosttyTerminalViewWrapper: UIViewRepresentable {
    let surface: GhosttySurface
    let isFocused: Bool

    func makeUIView(context: Context) -> GhosttySurface {
        surface.setFocused(isFocused)
        return surface
    }

    func updateUIView(_ uiView: GhosttySurface, context: Context) {
        uiView.setFocused(isFocused)
    }
}
#endif
