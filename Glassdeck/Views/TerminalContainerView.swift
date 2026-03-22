#if canImport(UIKit)
import CoreLocation
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
    @Environment(AppSettings.self) private var appSettings
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SessionLifecycleCoordinator.self) private var lifecycleCoordinator
    @State private var showHelpBrowser = false
    @State private var selectedDisplayTarget: TerminalDisplayTarget = .iphone

    private var colorSchemeBinding: Binding<TerminalColorScheme> {
        terminalBinding(\.colorScheme)
    }

    private var fontSizeBinding: Binding<Double> {
        terminalBinding(\.fontSize)
    }

    private var cursorStyleBinding: Binding<TerminalConfiguration.CursorStyle> {
        terminalBinding(\.cursorStyle)
    }

    private var cursorBlinkBinding: Binding<Bool> {
        terminalBinding(\.cursorBlink)
    }

    private var scrollbackLinesBinding: Binding<Int> {
        terminalBinding(\.scrollbackLines)
    }

    private var bellSoundBinding: Binding<Bool> {
        terminalBinding(\.bellSound)
    }

    private var autoReconnectBinding: Binding<Bool> {
        Binding(
            get: { appSettings.autoReconnect },
            set: {
                appSettings.autoReconnect = $0
                lifecycleCoordinator.refreshSettingsDrivenRuntime()
            }
        )
    }

    private var reconnectDelayBinding: Binding<Double> {
        Binding(
            get: { appSettings.reconnectDelay },
            set: {
                appSettings.reconnectDelay = $0
                lifecycleCoordinator.refreshSettingsDrivenRuntime()
            }
        )
    }

    private var maxReconnectAttemptsBinding: Binding<Int> {
        Binding(
            get: { appSettings.maxReconnectAttempts },
            set: {
                appSettings.maxReconnectAttempts = $0
                lifecycleCoordinator.refreshSettingsDrivenRuntime()
            }
        )
    }

    private var backgroundPersistenceEnabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.backgroundPersistenceEnabled },
            set: {
                appSettings.backgroundPersistenceEnabled = $0
                lifecycleCoordinator.refreshSettingsDrivenRuntime()
            }
        )
    }

    private var backgroundPersistenceController: SessionBackgroundPersistenceController {
        lifecycleCoordinator.backgroundPersistenceController
    }

    private var reconnectDelayText: String {
        String(format: "%.1fs", appSettings.reconnectDelay)
    }

    private var selectedTerminalConfig: TerminalConfiguration {
        appSettings.terminalConfig(for: selectedDisplayTarget)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-Reconnect", isOn: autoReconnectBinding)

                    HStack {
                        Text("Reconnect Delay")
                        Spacer()
                        Text(reconnectDelayText)
                            .foregroundStyle(.secondary)
                        Stepper(
                            "",
                            value: reconnectDelayBinding,
                            in: 0.5...30,
                            step: 0.5
                        )
                        .labelsHidden()
                    }

                    HStack {
                        Text("Max Attempts")
                        Spacer()
                        Text("\(appSettings.maxReconnectAttempts)")
                            .foregroundStyle(.secondary)
                        Stepper(
                            "",
                            value: maxReconnectAttemptsBinding,
                            in: 1...20
                        )
                        .labelsHidden()
                    }
                } header: {
                    Text("Session Persistence")
                } footer: {
                    Text("Dropped sessions are restored on foreground return, using the saved reconnect policy below.")
                }

                Section {
                    Toggle(
                        "Keep Live Sessions Active in Background",
                        isOn: backgroundPersistenceEnabledBinding
                    )

                    LabeledContent(
                        "Location Services",
                        value: backgroundPersistenceController.isLocationServicesEnabled ? "Available" : "Unavailable"
                    )

                    LabeledContent(
                        "Runtime",
                        value: backgroundPersistenceController.isRuntimeActive ? "Active" : "Inactive"
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(backgroundPersistenceController.authorizationDescription)
                        Text(backgroundPersistenceController.statusMessage)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if appSettings.backgroundPersistenceEnabled,
                       backgroundPersistenceController.authorizationStatus == .notDetermined {
                        Button("Request Location Permission") {
                            lifecycleCoordinator.refreshSettingsDrivenRuntime()
                        }
                    }
                } header: {
                    Text("Background Persistence")
                } footer: {
                    Text("Uses Core Location background activity only while live sessions exist. This is best-effort and may affect battery life.")
                }

                Section {
                    Picker("Target", selection: $selectedDisplayTarget) {
                        ForEach(TerminalDisplayTarget.allCases) { target in
                            Text(target.label).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("terminal-settings-target-picker")
                } header: {
                    Text("Terminal Profile")
                } footer: {
                    Text("iPhone and External Monitor profiles are stored separately and apply immediately to matching live sessions.")
                }

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
                        Text("\(Int(selectedTerminalConfig.fontSize.rounded()))pt")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("terminal-settings-font-size-value")
                        Stepper("", value: fontSizeBinding, in: 8...32, step: 1)
                            .labelsHidden()
                            .accessibilityIdentifier("terminal-settings-font-size-stepper")
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
                        Text("\(selectedTerminalConfig.scrollbackLines)")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("terminal-settings-scrollback-value")
                        Stepper(
                            "",
                            value: scrollbackLinesBinding,
                            in: 1_000...100_000,
                            step: 1_000
                        )
                        .labelsHidden()
                        .accessibilityIdentifier("terminal-settings-scrollback-stepper")
                    }

                    Toggle("Bell Sound", isOn: bellSoundBinding)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Applying a profile live preserves the SSH connection, but the visible terminal view may be recreated.")
                }

                Section {
                    Button {
                        showHelpBrowser = true
                    } label: {
                        Label("SSH Reference", systemImage: "book")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDismissButton()
                }
            }
            .sheet(isPresented: $showHelpBrowser) {
                HelpBrowserView()
            }
            .overlay(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("terminal-settings-profile-summary")
                    .accessibilityValue(terminalProfileSummaryValue)
            }
        }
    }

    private func terminalBinding<Value>(
        _ keyPath: WritableKeyPath<TerminalConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { appSettings.terminalConfig(for: selectedDisplayTarget)[keyPath: keyPath] },
            set: { newValue in
                var configuration = appSettings.terminalConfig(for: selectedDisplayTarget)
                configuration[keyPath: keyPath] = newValue
                appSettings.setTerminalConfig(configuration, for: selectedDisplayTarget)
                Task {
                    await sessionManager.refreshTerminalConfiguration(for: selectedDisplayTarget)
                }
            }
        )
    }

    private var terminalProfileSummaryValue: String {
        [
            "target=\(selectedDisplayTarget.rawValue)",
            "fontSize=\(Int(selectedTerminalConfig.fontSize.rounded()))",
            "scrollback=\(selectedTerminalConfig.scrollbackLines)",
            "scheme=\(selectedTerminalConfig.colorScheme.rawValue)",
        ].joined(separator: "|")
    }
}

private struct SheetDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
    }
}
#endif
