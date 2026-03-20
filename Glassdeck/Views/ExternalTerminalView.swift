import SwiftUI

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
