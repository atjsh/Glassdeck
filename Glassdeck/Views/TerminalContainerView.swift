import SwiftUI

/// Terminal container with Liquid Glass floating toolbar.
///
/// Wraps the terminal surface view with a GlassEffectContainer toolbar
/// providing quick actions: disconnect, new tab, AI assist, and settings.
/// Handles the full connection lifecycle including password prompting.
struct TerminalContainerView: View {
    let profile: ConnectionProfile
    @Environment(SessionManager.self) private var sessionManager
    @State private var showAIAssistant = false
    @State private var showSettings = false
    @State private var showPasswordPrompt = false
    @State private var password = ""
    @State private var showDisplayPicker = false

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
                    onDisplay: { showDisplayPicker = true },
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
        .sheet(isPresented: $showDisplayPicker) {
            DisplayRoutingPicker()
        }
        .alert("Password Required", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $password)
            Button("Connect") {
                Task {
                    await sessionManager.connect(to: profile, password: password)
                    password = ""
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter password for \(profile.username)@\(profile.host)")
        }
        .task {
            if profile.authMethod == .password {
                showPasswordPrompt = true
            } else {
                // Key auth — connect immediately
                await sessionManager.connect(to: profile)
            }
        }
    }
}

/// Floating glass toolbar with morphing action buttons.
struct GlassToolbar: View {
    let onDisconnect: () -> Void
    let onNewTab: () -> Void
    let onAI: () -> Void
    let onDisplay: () -> Void
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
                    icon: "rectangle.on.rectangle",
                    tint: .orange,
                    action: onDisplay
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

/// Picker to route sessions to external display.
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
                                Image(systemName: session.isOnExternalDisplay
                                    ? "display"
                                    : "terminal")
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
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Terminal settings with theme picker, font controls, and behavior options.
struct TerminalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = TerminalConfiguration()
    @State private var showHelpBrowser = false

    var body: some View {
        NavigationStack {
            Form {
                // Appearance
                Section("Appearance") {
                    Picker("Color Scheme", selection: $config.colorScheme) {
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
                        Text("\(Int(config.fontSize))pt")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $config.fontSize, in: 8...32, step: 1)
                            .labelsHidden()
                    }

                    Picker("Cursor", selection: $config.cursorStyle) {
                        ForEach(TerminalConfiguration.CursorStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }

                    Toggle("Cursor Blink", isOn: $config.cursorBlink)
                }

                // Behavior
                Section("Behavior") {
                    HStack {
                        Text("Scrollback Lines")
                        Spacer()
                        Text("\(config.scrollbackLines)")
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Bell Sound", isOn: $config.bellSound)
                }

                // Help
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
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showHelpBrowser) {
                HelpBrowserView()
            }
        }
    }
}
