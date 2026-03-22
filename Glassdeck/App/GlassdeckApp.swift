#if canImport(UIKit)
import GlassdeckCore
import SwiftUI

enum AppRootTab: Hashable {
    case sessions
    case connections
}

enum AppLaunchRouting {
    static func shouldScheduleDeferredRoute(
        shouldOpenActiveSessionOnLaunch: Bool,
        appliedLaunchRouting: Bool,
        launchRoutingScheduled: Bool,
        hasActiveSession: Bool,
        isActiveSessionPresentable: Bool,
        allowHostBackedLaunchFallback: Bool = false
    ) -> Bool {
        shouldOpenActiveSessionOnLaunch
            && !appliedLaunchRouting
            && !launchRoutingScheduled
            && (hasActiveSession || allowHostBackedLaunchFallback)
            && isActiveSessionPresentable
    }
}

@main
@MainActor
struct GlassdeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let sessionManager = GlassdeckEnvironment.sessionManager
    private let connectionStore = GlassdeckEnvironment.connectionStore
    private let appSettings = GlassdeckEnvironment.appSettings
    private let lifecycleCoordinator = GlassdeckEnvironment.lifecycleCoordinator

    init() {
        UITestLaunchSupport.configureIfNeeded(
            sessionManager: GlassdeckEnvironment.sessionManager,
            connectionStore: GlassdeckEnvironment.connectionStore,
            appSettings: GlassdeckEnvironment.appSettings
        )
        GlassdeckEnvironment.lifecycleCoordinator.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(connectionStore)
                .environment(appSettings)
                .environment(lifecycleCoordinator)
        }
    }
}

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(SessionLifecycleCoordinator.self) private var lifecycleCoordinator
    @State private var selectedTab: AppRootTab = .connections
    @State private var sessionsPath: [UUID] = []
    @State private var appliedLaunchRouting = false
    @State private var launchRoutingScheduled = false

    private var shouldOpenActiveSessionOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestOpenActiveSession")
    }

    private var hostBackedLaunchRoutingSession: SSHSessionModel? {
        if let activeSession = sessionManager.activeSession {
            return activeSession
        }

        guard UITestLaunchSupport.shouldRouteAfterPreservedHostState else {
            return nil
        }

        return sessionManager.sessions
            .filter {
                $0.shouldRestoreConnectionOnForeground
                || $0.isConnected
                || $0.status == .reconnecting
            }
            .sorted {
                ($0.connectedAt ?? .distantPast) > ($1.connectedAt ?? .distantPast)
            }
            .first
            ?? sessionManager.sessions
                .sorted {
                    ($0.connectedAt ?? .distantPast) > ($1.connectedAt ?? .distantPast)
                }
                .first
    }

    private var isLaunchSessionRouteReady: Bool {
        guard let session = hostBackedLaunchRoutingSession else { return false }
        if sessionManager.isSessionDetailPresentable(for: session) {
            return true
        }
        return UITestLaunchSupport.isPreservingHostState && session.surface != nil
    }

    private var isLaunchSessionRouteEligible: Bool {
        if isLaunchSessionRouteReady {
            return true
        }

        return UITestLaunchSupport.shouldRouteAfterPreservedHostState && hostBackedLaunchRoutingSession != nil
    }

    private var launchRoutingSignature: String {
        let launchSession = hostBackedLaunchRoutingSession
        return [
            launchSession?.id.uuidString ?? "none",
            launchSession.map { sessionManager.isSessionDetailPresentable(for: $0) ? "ready" : "pending" } ?? "missing",
            String(sessionManager.presentationRevision),
            String(selectedTab == .sessions),
            String(sessionsPath.count),
            String(appliedLaunchRouting)
        ].joined(separator: "|")
    }

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
        .onAppear {
            lifecycleCoordinator.start()
            synchronizeRootState()
            scheduleDeferredLaunchRoutingIfNeeded()
        }
        .onChange(of: sessionManager.sessions.count) { _, _ in
            synchronizeRootState()
            scheduleDeferredLaunchRoutingIfNeeded()
        }
        .onChange(of: launchRoutingSignature) { _, _ in
            scheduleDeferredLaunchRoutingIfNeeded()
        }
        .onChange(of: appSettings.backgroundPersistenceEnabled) { _, _ in
            lifecycleCoordinator.refreshSettingsDrivenRuntime()
        }
        .onChange(of: appSettings.autoReconnect) { _, _ in
            lifecycleCoordinator.refreshSettingsDrivenRuntime()
        }
        .onChange(of: appSettings.reconnectDelay) { _, _ in
            lifecycleCoordinator.refreshSettingsDrivenRuntime()
        }
        .onChange(of: appSettings.maxReconnectAttempts) { _, _ in
            lifecycleCoordinator.refreshSettingsDrivenRuntime()
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
        if sessionManager.sessions.isEmpty {
            selectedTab = .connections
            sessionsPath = []
        }
    }

    private func scheduleDeferredLaunchRoutingIfNeeded() {
        if launchRoutingScheduled || appliedLaunchRouting || !shouldOpenActiveSessionOnLaunch {
            if shouldOpenActiveSessionOnLaunch && !shouldOpenSessionRouteSessionEligible {
                UITestLaunchSupport.setLaunchRoutingState(.waitingForSession)
            }
            return
        }

        guard let session = hostBackedLaunchRoutingSession else {
            UITestLaunchSupport.setLaunchRoutingState(.waitingForSession)
            return
        }

        guard AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: shouldOpenActiveSessionOnLaunch,
            appliedLaunchRouting: appliedLaunchRouting,
            launchRoutingScheduled: launchRoutingScheduled,
            hasActiveSession: sessionManager.activeSession != nil,
            isActiveSessionPresentable: isLaunchSessionRouteEligible,
            allowHostBackedLaunchFallback: UITestLaunchSupport.shouldRouteAfterPreservedHostState
        ) else {
            if shouldOpenActiveSessionOnLaunch && sessionManager.sessions.isEmpty {
                UITestLaunchSupport.setLaunchRoutingState(.waitingForSession)
            }
            return
        }

        guard isSessionRouteReady(session) else {
            UITestLaunchSupport.setLaunchRoutingState(.waitingForRouteableSession)
            return
        }

        launchRoutingScheduled = true
        Task { @MainActor in
            defer { launchRoutingScheduled = false }
            // Yield once so the view hierarchy settles before navigating.
            await Task.yield()
            selectedTab = .sessions
            sessionsPath = [session.id]
            appliedLaunchRouting = true
            UITestLaunchSupport.setLaunchRoutingState(.routeApplied)
        }
    }

    private func isSessionRouteReady(_ session: SSHSessionModel) -> Bool {
        if sessionManager.isSessionDetailPresentable(for: session) { return true }
        return UITestLaunchSupport.isPreservingHostState && session.surface != nil
    }

    private var shouldOpenSessionRouteSessionEligible: Bool {
        if !shouldOpenActiveSessionOnLaunch {
            return false
        }

        if sessionManager.activeSession != nil {
            return true
        }

        return hostBackedLaunchRoutingSession != nil
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
