#if canImport(UIKit)
import GlassdeckCore
import SwiftUI

enum AppRootTab: Hashable {
    case sessions
    case connections
}

@main
@MainActor
struct GlassdeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let sessionManager = GlassdeckEnvironment.sessionManager
    private let connectionStore = GlassdeckEnvironment.connectionStore
    private let appSettings = GlassdeckEnvironment.appSettings

    init() {
        UITestLaunchSupport.configureIfNeeded(
            sessionManager: GlassdeckEnvironment.sessionManager,
            connectionStore: GlassdeckEnvironment.connectionStore,
            appSettings: GlassdeckEnvironment.appSettings
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(connectionStore)
                .environment(appSettings)
        }
    }
}

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var selectedTab: AppRootTab = .connections
    @State private var sessionsPath: [UUID] = []
    @State private var appliedLaunchRouting = false

    var body: some View {
        TabView(selection: $selectedTab) {
            SessionsRootView(
                selectedTab: $selectedTab,
                sessionsPath: $sessionsPath
            )
            .tag(AppRootTab.sessions)
            .tabItem {
                Label("Sessions", systemImage: "rectangle.on.rectangle")
            }

            ConnectionsRootView(
                selectedTab: $selectedTab,
                sessionsPath: $sessionsPath
            )
            .tag(AppRootTab.connections)
            .tabItem {
                Label("Connections", systemImage: "server.rack")
            }
        }
        .onAppear(perform: synchronizeRootState)
        .onChange(of: sessionManager.sessions.count) { _, _ in
            synchronizeRootState()
        }
        .sheet(isPresented: Binding(
            get: { sessionManager.showConnectionPicker },
            set: { sessionManager.showConnectionPicker = $0 }
        )) {
            ConnectionPickerSheet { profile in
                Task {
                    if let session = await sessionManager.connect(to: profile) {
                        sessionManager.setActiveSession(
                            id: session.id,
                            focusSurface: !UITestLaunchSupport.exposesTerminalRenderSummary
                        )
                        sessionsPath = [session.id]
                        selectedTab = .sessions
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func synchronizeRootState() {
        if !appliedLaunchRouting,
           ProcessInfo.processInfo.arguments.contains("-uiTestOpenActiveSession"),
           let activeSession = sessionManager.activeSession {
            selectedTab = .sessions
            sessionsPath = [activeSession.id]
            appliedLaunchRouting = true
            return
        }

        if selectedTab == .sessions && sessionManager.sessions.isEmpty {
            selectedTab = .connections
        } else if sessionManager.activeSession != nil && sessionsPath.isEmpty {
            selectedTab = .sessions
        } else if sessionManager.sessions.isEmpty {
            selectedTab = .connections
        }
    }
}

struct ConnectionPickerSheet: View {
    let onSelect: (ConnectionProfile) -> Void
    @Environment(ConnectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.connections) { profile in
                Button {
                    onSelect(profile)
                    dismiss()
                } label: {
                    ConnectionRow(profile: profile)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
#endif
