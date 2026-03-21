#if canImport(UIKit)
import SwiftUI
import GlassdeckCore

/// Manages the active terminal session displayed on an external monitor.
///
/// Shows the terminal full-screen at the monitor's native resolution with
/// a minimal glass-effect HUD overlay for connection status.
struct ExternalTerminalView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        ZStack {
            if let session = sessionManager.externalDisplaySession {
                TerminalSurfaceView(session: session)
                    .ignoresSafeArea()

                RemotePointerOverlay(session: session)
                    .allowsHitTesting(false)

                // Minimal glass HUD in top-right corner
                VStack {
                    HStack {
                        Spacer()
                        ConnectionStatusPill(session: session)
                            .padding()
                    }
                    Spacer()
                }
            } else {
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No session assigned to external display")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RemotePointerOverlay: View {
    let session: SSHSessionModel

    var body: some View {
        if session.remotePointerOverlayState.isVisible {
            switch session.remotePointerOverlayState.mode {
            case .mouse:
                pointer
            case .cursor:
                reticle
            }
        }
    }

    private var pointer: some View {
        let point = session.terminalInteractionGeometry.viewPoint(
            forSurfacePixelPoint: session.remotePointerOverlayState.surfacePixelPoint
        )

        return Image(systemName: session.remotePointerOverlayState.isDragging ? "cursorarrow.click.2" : "cursorarrow.motionlines")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(10)
            .background(.black.opacity(0.6), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1)
            )
            .position(point)
    }

    private var reticle: some View {
        guard let cell = session.remotePointerOverlayState.cellPosition else {
            return AnyView(EmptyView())
        }

        let rect = session.terminalInteractionGeometry.viewRect(for: cell)
        return AnyView(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(.white.opacity(0.95), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.12))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        )
    }
}

struct ConnectionStatusPill: View {
    let session: SSHSessionModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isConnected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(session.displayName)
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.clear, in: .capsule)
    }
}

#endif
