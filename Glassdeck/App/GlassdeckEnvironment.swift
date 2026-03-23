import GlassdeckCore
import Foundation

@MainActor
enum GlassdeckEnvironment {
    private static let preserveHostBackedUITestStateEnvironmentKey = "GLASSDECK_UI_TEST_PRESERVE_HOST_STATE"

    static let appSettings: AppSettings = {
        resetStateForHostBackedTestsIfNeeded()
        return AppSettings()
    }()
    static let connectionStore = ConnectionStore()
    static let sessionManager = SessionManager(appSettings: appSettings)
    static let lifecycleCoordinator: SessionLifecycleCoordinator = {
        let coordinator = SessionLifecycleCoordinator(
            sessionManager: sessionManager,
            appSettings: appSettings
        )
        sessionManager.lifecycleDelegate = coordinator
        return coordinator
    }()

    private static func resetStateForHostBackedTestsIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            return
        }
        guard ProcessInfo.processInfo.environment[preserveHostBackedUITestStateEnvironmentKey] != "1" else {
            return
        }
        guard UITestLaunchSupport.currentScenario == nil else { return }

        SessionPersistenceStore().clear()
        SessionCredentialStore().removeAll()
    }
}
