#if canImport(UIKit)
import GlassdeckCore
import SwiftUI

private enum SessionPresentationSheet: Identifiable {
    case sftp(ConnectionProfile)
    case displayRouting
    case settings
    case help

    var id: String {
        switch self {
        case .sftp(let profile):
            "sftp-\(profile.id.uuidString)"
        case .displayRouting:
            "display-routing"
        case .settings:
            "terminal-settings"
        case .help:
            "help-browser"
        }
    }
}

struct SessionDetailView: View {
    let sessionID: UUID

    @Environment(SessionManager.self) private var sessionManager
    @State private var activeSheet: SessionPresentationSheet?
    @State private var appliedLaunchSheet = false

    private var session: SSHSessionModel? {
        sessionManager.session(with: sessionID)
    }

    var body: some View {
        Group {
            if let session {
                SessionDetailContent(session: session, activeSheet: $activeSheet)
            } else {
                ContentUnavailableView(
                    "Session Closed",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("This session is no longer available.")
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-detail-view")
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.id) {
            guard !appliedLaunchSheet else { return }
            guard let session else { return }
            if ProcessInfo.processInfo.arguments.contains("-uiTestPresentSFTP") {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                activeSheet = .sftp(session.profile)
            }
            appliedLaunchSheet = true
        }
    }
}

private struct SessionDetailContent: View {
    let session: SSHSessionModel
    @Binding var activeSheet: SessionPresentationSheet?

    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var appSettings

    private var exposesRenderSummaryForUITests: Bool {
        UITestLaunchSupport.exposesTerminalRenderSummary
    }

    private var showingRemoteTrackpad: Bool {
        sessionManager.shouldShowRemoteTrackpad(for: session)
    }

    private var terminalPresentationReady: Bool {
        sessionManager.isTerminalPresentationReady(for: session)
    }

    private var terminalBackgroundColor: Color {
        let theme = (
            session.surface?.terminalConfiguration
            ?? appSettings.terminalConfig(for: sessionManager.terminalDisplayTarget(for: session))
        ).colorScheme.theme
        return Color(
            red: Double(theme.background.r) / 255,
            green: Double(theme.background.g) / 255,
            blue: Double(theme.background.b) / 255
        )
    }

    private var terminalRenderSummaryValue: String {
        if !showingRemoteTrackpad && !terminalPresentationReady {
            if session.surface == nil {
                return "[terminal pending] Restoring terminal surface"
            }
            return "[terminal pending] Preparing terminal"
        }
        if session.terminalVisibleTextSummary.isEmpty {
            return session.terminalRenderFailureReason ?? ""
        }
        if let terminalRenderFailureReason = session.terminalRenderFailureReason {
            return "\(session.terminalVisibleTextSummary)\n[render unavailable] \(terminalRenderFailureReason)"
        }
        return session.terminalVisibleTextSummary
    }

    private var terminalAnimationProgressValue: String? {
        session.terminalAnimationProgress?.accessibilityValue
    }

    var body: some View {
        ZStack {
            sessionWorkspace

            if let recoveryState = recoveryState {
                SessionRecoveryPanel(
                    state: recoveryState,
                    reconnect: {
                        Task {
                            _ = await sessionManager.reconnect(sessionID: session.id)
                        }
                    },
                    close: {
                        sessionManager.closeSession(id: session.id)
                    }
                )
                .padding(24)
            }
        }
        .background {
            (showingRemoteTrackpad ? Color(uiColor: .systemGroupedBackground) : terminalBackgroundColor)
                .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(showingRemoteTrackpad ? .regularMaterial : .ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(showingRemoteTrackpad ? .light : .dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SessionTitleView(session: session)
            }

            if session.isConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .sftp(session.profile)
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    .accessibilityIdentifier("session-files-button")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if session.isConnected {
                        Button {
                            sessionManager.disconnect(sessionID: session.id)
                        } label: {
                            Label("Disconnect", systemImage: "bolt.slash")
                        }
                    } else {
                        Button {
                            Task {
                                _ = await sessionManager.reconnect(sessionID: session.id)
                            }
                        } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                    }

                    Button {
                        activeSheet = .displayRouting
                    } label: {
                        Label("Display Routing", systemImage: "display.2")
                    }

                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    Button {
                        activeSheet = .help
                    } label: {
                        Label("SSH Reference", systemImage: "book")
                    }

                    Button(role: .destructive) {
                        sessionManager.closeSession(id: session.id)
                    } label: {
                        Label("Close Session", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("session-menu-button")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sftp(let profile):
                SFTPBrowserView(profile: profile)
                    .presentationDetents([.large])
            case .displayRouting:
                DisplayRoutingPicker()
                    .presentationDetents([.medium, .large])
            case .settings:
                TerminalSettingsView()
                    .presentationDetents([.large])
            case .help:
                HelpBrowserView()
                    .presentationDetents([.large])
            }
        }
        .onAppear {
            sessionManager.setActiveSession(
                id: session.id,
                focusSurface: !exposesRenderSummaryForUITests
            )
        }
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                if exposesRenderSummaryForUITests {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("terminal-render-summary")
                        .accessibilityValue(terminalRenderSummaryValue)
                }

                if let terminalAnimationProgressValue {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("terminal-animation-progress")
                        .accessibilityValue(terminalAnimationProgressValue)
                }
            }
        }
    }

    @ViewBuilder
    private var sessionWorkspace: some View {
        if showingRemoteTrackpad {
            RemoteTrackpadView(session: session)
        } else {
            ZStack(alignment: .top) {
                TerminalSurfaceView(session: session)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .accessibilityIdentifier("terminal-surface-view")

                if !terminalPresentationReady {
                    TerminalPresentationPlaceholderView(session: session)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .accessibilityIdentifier("terminal-presentation-placeholder")
                }

                if let statusBannerState {
                    InlineStatusBanner(
                        label: statusBannerState.label,
                        systemImage: statusBannerState.systemImage,
                        tint: statusBannerState.tint
                    )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }
        }
    }

    private var statusBannerState: (label: String, systemImage: String, tint: Color)? {
        switch session.status {
        case .connecting:
            ("Connecting to \(session.profile.host)…", "bolt.horizontal", .blue)
        case .authenticating:
            ("Authenticating…", "lock.shield", .blue)
        case .reconnecting:
            (session.reconnectState.label ?? "Reconnecting…", "arrow.clockwise", .orange)
        case .connected, .disconnected, .failed:
            nil
        }
    }

    private var recoveryState: SessionRecoveryState? {
        switch session.status {
        case .failed(let message):
            SessionRecoveryState(
                title: "Session Unavailable",
                message: message,
                tint: .red,
                systemImage: "exclamationmark.triangle"
            )
        case .disconnected:
            SessionRecoveryState(
                title: "Disconnected",
                message: "Reconnect to resume this terminal session.",
                tint: .secondary,
                systemImage: "bolt.slash"
            )
        case .connected, .connecting, .authenticating, .reconnecting:
            nil
        }
    }
}

struct TerminalPresentationPlaceholderView: View {
    let session: SSHSessionModel

    private var title: String {
        switch session.status {
        case .connecting, .authenticating, .reconnecting:
            session.status.label
        case .connected:
            "Preparing Terminal…"
        case .disconnected:
            "Terminal Unavailable"
        case .failed:
            "Terminal Unavailable"
        }
    }

    private var subtitle: String {
        if let reason = session.terminalRenderFailureReason, !reason.isEmpty {
            return reason
        }
        if session.surface == nil {
            return "Restoring the terminal surface for this session."
        }
        return "Waiting for the terminal to finish its first render."
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if case .failed = session.status {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }

                Text(title)
                    .font(.body.monospaced())
                    .foregroundStyle(.white.opacity(0.82))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

private struct SessionTitleView: View {
    let session: SSHSessionModel

    var body: some View {
        VStack(spacing: 2) {
            Text(session.shortName)
                .font(.headline)
                .lineLimit(1)
            Text("\(session.profile.username)@\(session.profile.host)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityIdentifier("session-detail-view")
    }
}
#endif
