#if canImport(UIKit)
import CoreLocation
import GlassdeckCore
import SwiftUI

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

struct SheetDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
    }
}
#endif
