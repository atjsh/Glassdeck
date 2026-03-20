import SwiftUI

/// Terminal container with Liquid Glass floating toolbar.
///
/// Wraps the terminal surface view with a GlassEffectContainer toolbar
/// providing quick actions: disconnect, new tab, AI assist, and settings.
struct TerminalContainerView: View {
    let profile: ConnectionProfile
    @Environment(SessionManager.self) private var sessionManager
    @State private var showAIAssistant = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Terminal surface (full bleed)
            if let session = sessionManager.activeSession {
                TerminalSurfaceView(session: session)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else {
                Color.black
                    .ignoresSafeArea()
                ProgressView("Connecting…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            // Floating glass toolbar
            VStack {
                Spacer()
                GlassToolbar(
                    onDisconnect: { sessionManager.disconnect() },
                    onNewTab: { sessionManager.openNewTab() },
                    onAI: { showAIAssistant = true },
                    onSettings: { showSettings = true }
                )
                .padding(.bottom, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAIAssistant) {
            AIOverlayView()
        }
        .sheet(isPresented: $showSettings) {
            TerminalSettingsView()
        }
        .task {
            await sessionManager.connect(to: profile)
        }
    }
}

/// Floating glass toolbar with morphing action buttons.
struct GlassToolbar: View {
    let onDisconnect: () -> Void
    let onNewTab: () -> Void
    let onAI: () -> Void
    let onSettings: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                ToolbarButton(
                    icon: "xmark.circle",
                    tint: .red,
                    action: onDisconnect
                )
                ToolbarButton(
                    icon: "plus.rectangle.on.rectangle",
                    tint: .blue,
                    action: onNewTab
                )
                ToolbarButton(
                    icon: "sparkles",
                    tint: .purple,
                    action: onAI
                )
                ToolbarButton(
                    icon: "gearshape",
                    tint: .gray,
                    action: onSettings
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}

struct ToolbarButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .glassEffect(.regular.tint(tint), in: .circle)
    }
}

/// Placeholder for terminal settings
struct TerminalSettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Terminal Settings")
                .navigationTitle("Settings")
        }
    }
}
