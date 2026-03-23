import Foundation
import GlassdeckCore
import Observation

struct SessionBackgroundPersistenceRuntime {
    let setFeatureEnabled: @MainActor (Bool) -> Void
    let setHasLiveSessions: @MainActor (Bool) -> Void
    let requestAuthorizationIfNeeded: @MainActor () -> Void
    let resumeIfNeeded: @MainActor () -> Void

    init(
        setFeatureEnabled: @escaping @MainActor (Bool) -> Void,
        setHasLiveSessions: @escaping @MainActor (Bool) -> Void,
        requestAuthorizationIfNeeded: @escaping @MainActor () -> Void,
        resumeIfNeeded: @escaping @MainActor () -> Void
    ) {
        self.setFeatureEnabled = setFeatureEnabled
        self.setHasLiveSessions = setHasLiveSessions
        self.requestAuthorizationIfNeeded = requestAuthorizationIfNeeded
        self.resumeIfNeeded = resumeIfNeeded
    }

    static func live(
        controller: SessionBackgroundPersistenceController
    ) -> SessionBackgroundPersistenceRuntime {
        SessionBackgroundPersistenceRuntime(
            setFeatureEnabled: controller.setFeatureEnabled,
            setHasLiveSessions: controller.setHasLiveSessions,
            requestAuthorizationIfNeeded: controller.requestAuthorizationIfNeeded,
            resumeIfNeeded: controller.resumeIfNeeded
        )
    }
}

@Observable
@MainActor
final class SessionLifecycleCoordinator: SessionManagerLifecycleDelegate {
    let sessionManager: SessionManager
    let appSettings: AppSettings
    let backgroundPersistenceController: SessionBackgroundPersistenceController

    private var hasStarted = false
    @ObservationIgnored private let backgroundPersistenceRuntime: SessionBackgroundPersistenceRuntime

    init(
        sessionManager: SessionManager,
        appSettings: AppSettings,
        backgroundPersistenceController: SessionBackgroundPersistenceController = SessionBackgroundPersistenceController(),
        backgroundPersistenceRuntime: SessionBackgroundPersistenceRuntime? = nil
    ) {
        self.sessionManager = sessionManager
        self.appSettings = appSettings
        self.backgroundPersistenceController = backgroundPersistenceController
        self.backgroundPersistenceRuntime =
            backgroundPersistenceRuntime
            ?? SessionBackgroundPersistenceRuntime.live(controller: backgroundPersistenceController)
    }

    func start() {
        guard !hasStarted else {
            syncBackgroundPersistence()
            sessionManager.resumeRestorableSessionsIfNeeded()
            return
        }

        hasStarted = true
        sessionManager.restorePersistedSessionsIfNeeded()
        sessionManager.refreshReconnectConfiguration()
        sessionManager.resumeRestorableSessionsIfNeeded()
        syncBackgroundPersistence()
    }

    func handleAppDidBecomeActive() {
        sessionManager.handleAppDidBecomeActive()
        syncBackgroundPersistence()
    }

    func handleAppDidEnterBackground() {
        sessionManager.handleAppDidEnterBackground()
        syncBackgroundPersistence()
    }

    func refreshSettingsDrivenRuntime() {
        sessionManager.refreshReconnectConfiguration()
        syncBackgroundPersistence(requestAuthorizationIfNeeded: appSettings.backgroundPersistenceEnabled)
    }

    func sessionManagerDidChangeSessions(_ sessionManager: SessionManager) {
        syncBackgroundPersistence()
    }

    private func syncBackgroundPersistence(requestAuthorizationIfNeeded: Bool = false) {
        backgroundPersistenceRuntime.setFeatureEnabled(appSettings.backgroundPersistenceEnabled)
        backgroundPersistenceRuntime.setHasLiveSessions(sessionManager.hasLiveSessionsNeedingRuntimeSupport)

        if requestAuthorizationIfNeeded {
            backgroundPersistenceRuntime.requestAuthorizationIfNeeded()
        } else {
            backgroundPersistenceRuntime.resumeIfNeeded()
        }
    }
}
