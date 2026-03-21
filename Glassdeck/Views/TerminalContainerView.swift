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

    private var terminalBackgroundColor: Color {
        let theme = (session.surface?.terminalConfiguration ?? appSettings.terminalConfig).colorScheme.theme
        return Color(
            red: Double(theme.background.r) / 255,
            green: Double(theme.background.g) / 255,
            blue: Double(theme.background.b) / 255
        )
    }

    private var terminalRenderSummaryValue: String {
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
        .background(showingRemoteTrackpad ? Color(uiColor: .systemGroupedBackground) : terminalBackgroundColor)
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

                    if showingRemoteTrackpad {
                        Button {
                            sessionManager.showLocalTerminalForCurrentVisit(sessionID: session.id)
                        } label: {
                            Label("View Local Terminal", systemImage: "rectangle.on.rectangle")
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
                        Label("Terminal Settings", systemImage: "gearshape")
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

private struct SessionRecoveryState {
    let title: String
    let message: String
    let tint: Color
    let systemImage: String
}

private struct SessionRecoveryPanel: View {
    let state: SessionRecoveryState
    let reconnect: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(state.tint)

            VStack(spacing: 8) {
                Text(state.title)
                    .font(.title3.weight(.semibold))
                Text(state.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Reconnect", action: reconnect)
                    .buttonStyle(.borderedProminent)
                Button("Close", role: .destructive, action: close)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityIdentifier("session-recovery-panel")
    }
}

struct DisplayRoutingPicker: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Route to External Display") {
                    ForEach(sessionManager.sessions) { session in
                        Button {
                            sessionManager.routeToExternalDisplay(sessionID: session.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: session.isOnExternalDisplay ? "display" : "terminal")
                                Text(session.displayName)
                                Spacer()
                                if session.isOnExternalDisplay {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                if sessionManager.externalDisplaySessionID != nil {
                    Section {
                        Button("Clear External Display", role: .destructive) {
                            sessionManager.clearExternalDisplay()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("External Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetDismissButton()
                }
            }
        }
    }
}

struct TerminalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings
    @State private var showHelpBrowser = false

    private var colorSchemeBinding: Binding<TerminalColorScheme> {
        Binding(
            get: { appSettings.terminalConfig.colorScheme },
            set: { appSettings.terminalConfig.colorScheme = $0 }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { appSettings.terminalConfig.fontSize },
            set: { appSettings.terminalConfig.fontSize = $0 }
        )
    }

    private var cursorStyleBinding: Binding<TerminalConfiguration.CursorStyle> {
        Binding(
            get: { appSettings.terminalConfig.cursorStyle },
            set: { appSettings.terminalConfig.cursorStyle = $0 }
        )
    }

    private var cursorBlinkBinding: Binding<Bool> {
        Binding(
            get: { appSettings.terminalConfig.cursorBlink },
            set: { appSettings.terminalConfig.cursorBlink = $0 }
        )
    }

    private var scrollbackLinesBinding: Binding<Int> {
        Binding(
            get: { appSettings.terminalConfig.scrollbackLines },
            set: { appSettings.terminalConfig.scrollbackLines = $0 }
        )
    }

    private var bellSoundBinding: Binding<Bool> {
        Binding(
            get: { appSettings.terminalConfig.bellSound },
            set: { appSettings.terminalConfig.bellSound = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Color Scheme", selection: colorSchemeBinding) {
                        ForEach(TerminalColorScheme.allCases, id: \.self) { scheme in
                            HStack {
                                Circle()
                                    .fill(Color(
                                        red: Double(scheme.backgroundColor.r) / 255,
                                        green: Double(scheme.backgroundColor.g) / 255,
                                        blue: Double(scheme.backgroundColor.b) / 255
                                    ))
                                    .frame(width: 16, height: 16)
                                Text(scheme.rawValue)
                            }
                            .tag(scheme)
                        }
                    }

                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(appSettings.terminalConfig.fontSize))pt")
                            .foregroundStyle(.secondary)
                        Stepper("", value: fontSizeBinding, in: 8...32, step: 1)
                            .labelsHidden()
                    }

                    Picker("Cursor", selection: cursorStyleBinding) {
                        ForEach(TerminalConfiguration.CursorStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }

                    Toggle("Cursor Blink", isOn: cursorBlinkBinding)
                } header: {
                    Text("Appearance")
                }

                Section {
                    HStack {
                        Text("Scrollback Lines")
                        Spacer()
                        Text("\(appSettings.terminalConfig.scrollbackLines)")
                            .foregroundStyle(.secondary)
                        Stepper(
                            "",
                            value: scrollbackLinesBinding,
                            in: 1_000...100_000,
                            step: 1_000
                        )
                        .labelsHidden()
                    }

                    Toggle("Bell Sound", isOn: bellSoundBinding)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Changes apply to new and reconnected sessions.")
                }

                Section {
                    Button {
                        showHelpBrowser = true
                    } label: {
                        Label("SSH Reference", systemImage: "book")
                    }
                }
            }
            .navigationTitle("Terminal Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDismissButton()
                }
            }
            .sheet(isPresented: $showHelpBrowser) {
                HelpBrowserView()
            }
        }
    }
}

private struct SheetDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
    }
}
#endif
