import Foundation
@testable import Glassdeck
import GlassdeckCore
import XCTest

@MainActor
final class SessionPersistenceTests: XCTestCase {
    func testSessionPersistenceStoreRoundTripsSnapshot() throws {
        let suiteName = "Glassdeck.SessionPersistenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let profile = sampleProfile()
        let sessionID = UUID()
        let snapshot = PersistedSessionSnapshot(
            sessions: [
                PersistedSessionDescriptor(
                    id: sessionID,
                    profile: profile,
                    status: .connected,
                    connectedAt: Date(timeIntervalSince1970: 1_234),
                    reconnectState: .attempting(attempt: 2, maxAttempts: 5),
                    terminalTitle: "tester@example.com",
                    terminalSize: TerminalSize(columns: 120, rows: 32),
                    terminalPixelSize: TerminalPixelSize(width: 1440, height: 900),
                    scrollbackLines: 640,
                    shouldRestoreConnectionOnForeground: true,
                    isOnExternalDisplay: true
                )
            ],
            activeSessionID: sessionID,
            externalDisplaySessionID: sessionID
        )

        store.saveSnapshot(snapshot)

        XCTAssertEqual(store.loadSnapshot(), snapshot)
    }

    func testSessionCredentialStoreRoundTripsPassword() throws {
        let store = SessionCredentialStore(
            service: "Glassdeck.SessionCredentialStoreTests.\(UUID().uuidString)"
        )
        let profileID = UUID()
        defer {
            store.removeAll()
        }

        try store.storePassword("top-secret", for: profileID)
        XCTAssertEqual(store.password(for: profileID), "top-secret")

        try store.deletePassword(for: profileID)
        XCTAssertNil(store.password(for: profileID))
    }

    func testSessionManagerReconnectConfigReflectsAppSettings() {
        let defaults = isolatedDefaults(named: "ReconnectConfig")
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
        }

        let settings = AppSettings(defaults: defaults)
        settings.autoReconnect = false
        settings.reconnectDelay = 1.25
        settings.maxReconnectAttempts = 7

        let config = SessionManager.reconnectConfig(from: settings)

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.maxAttempts, 7)
        XCTAssertEqual(config.initialDelay, 1.25, accuracy: 0.001)
        XCTAssertEqual(config.maxDelay, 5.0, accuracy: 0.001)
        XCTAssertEqual(config.backoffMultiplier, 2.0, accuracy: 0.001)
    }

    func testSessionManagerRestoresPersistedPasswordSessionAndCredential() throws {
        let defaults = isolatedDefaults(named: "RestorePersistedSession")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.SessionRestoreCredentialTests.\(UUID().uuidString)"
        )
        let profileID = UUID()
        let sessionID = UUID()
        let profile = sampleProfile(id: profileID, authMethod: .password)
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        persistenceStore.saveSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: profile,
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 4_321),
                        reconnectState: .idle,
                        terminalTitle: "tester@restore",
                        terminalSize: TerminalSize(columns: 104, rows: 28),
                        terminalPixelSize: TerminalPixelSize(width: 1200, height: 840),
                        scrollbackLines: 512,
                        shouldRestoreConnectionOnForeground: true,
                        isOnExternalDisplay: true
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: sessionID
            )
        )
        try credentialStore.storePassword("restore-me", for: profileID)

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore
        )

        XCTAssertEqual(sessionManager.sessions.count, 1)
        XCTAssertEqual(sessionManager.activeSessionID, sessionID)
        XCTAssertEqual(sessionManager.externalDisplaySessionID, sessionID)

        let restoredSession = try XCTUnwrap(sessionManager.sessions.first)
        XCTAssertEqual(restoredSession.status, .reconnecting)
        XCTAssertEqual(restoredSession.connectionPassword, "restore-me")
        XCTAssertEqual(restoredSession.terminalTitle, "tester@restore")
        XCTAssertEqual(restoredSession.terminalSize, TerminalSize(columns: 104, rows: 28))
        XCTAssertEqual(restoredSession.terminalPixelSize, TerminalPixelSize(width: 1200, height: 840))
        XCTAssertEqual(restoredSession.scrollbackLines, 512)
        XCTAssertTrue(restoredSession.isOnExternalDisplay)
        XCTAssertTrue(restoredSession.shouldRestoreConnectionOnForeground)
        XCTAssertTrue(restoredSession.wasRestoredFromPersistence)
    }

    func testSessionManagerNormalizesPersistedLiveSessionWithoutRestoreFlag() throws {
        let defaults = isolatedDefaults(named: "NormalizePersistedLiveSession")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.NormalizePersistedLiveSession.\(UUID().uuidString)"
        )
        let sessionID = UUID()
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        persistenceStore.saveSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: sampleProfile(),
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 9_876),
                        reconnectState: .idle,
                        terminalTitle: "stale@example.com",
                        terminalSize: TerminalSize(columns: 100, rows: 30),
                        terminalPixelSize: TerminalPixelSize(width: 1200, height: 800),
                        scrollbackLines: 256,
                        shouldRestoreConnectionOnForeground: false,
                        isOnExternalDisplay: false
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: nil
            )
        )

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore
        )

        let restoredSession = try XCTUnwrap(sessionManager.sessions.first)
        XCTAssertEqual(restoredSession.status, .reconnecting)
        XCTAssertEqual(restoredSession.terminalTitle, "stale@example.com")
        XCTAssertTrue(restoredSession.shouldRestoreConnectionOnForeground)
        XCTAssertNil(restoredSession.surface)
    }

    func testLifecycleCoordinatorMarksConnectedSessionsForForegroundRestoreAndSyncsRuntime() {
        let defaults = isolatedDefaults(named: "LifecycleCoordinator")
        let settings = AppSettings(defaults: defaults)
        settings.backgroundPersistenceEnabled = true

        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.SessionLifecycleCredentialTests.\(UUID().uuidString)"
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        let sessionManager = SessionManager(
            appSettings: settings,
            persistenceStore: persistenceStore,
            credentialStore: credentialStore
        )
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .connected
        XCTAssertTrue(sessionManager.attachSyntheticSurfaceForPreview(
            to: session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "tester@example.com",
                transcript: "$ echo ok\nok\n$",
                terminalSize: TerminalSize(columns: 100, rows: 30)
            )
        ))
        sessionManager.replaceSessionsForPreview(
            [session],
            activeSessionID: session.id,
            externalDisplaySessionID: nil,
            hasExternalDisplayConnected: false
        )

        let recorder = BackgroundRuntimeRecorder()
        let coordinator = SessionLifecycleCoordinator(
            sessionManager: sessionManager,
            appSettings: settings,
            backgroundPersistenceRuntime: SessionBackgroundPersistenceRuntime(
                setFeatureEnabled: { recorder.featureEnabledValues.append($0) },
                setHasLiveSessions: { recorder.liveSessionValues.append($0) },
                requestAuthorizationIfNeeded: { recorder.requestAuthorizationCount += 1 },
                resumeIfNeeded: { recorder.resumeCount += 1 }
            )
        )
        sessionManager.lifecycleDelegate = coordinator

        coordinator.start()
        XCTAssertEqual(recorder.featureEnabledValues.last, true)
        XCTAssertEqual(recorder.liveSessionValues.last, true)
        XCTAssertEqual(recorder.resumeCount, 1)

        coordinator.handleAppDidEnterBackground()
        XCTAssertTrue(session.shouldRestoreConnectionOnForeground)
        XCTAssertEqual(recorder.resumeCount, 2)

        let persistedSnapshot = persistenceStore.loadSnapshot()
        XCTAssertEqual(
            persistedSnapshot?.sessions.first?.shouldRestoreConnectionOnForeground,
            true
        )

        coordinator.handleAppDidBecomeActive()
        XCTAssertEqual(recorder.resumeCount, 3)

        coordinator.refreshSettingsDrivenRuntime()
        XCTAssertEqual(recorder.requestAuthorizationCount, 1)
    }

    private func sampleProfile(
        id: UUID = UUID(),
        authMethod: AuthMethod = .sshKey
    ) -> ConnectionProfile {
        ConnectionProfile(
            id: id,
            name: "Restored",
            host: "example.com",
            port: 22,
            username: "tester",
            authMethod: authMethod
        )
    }

    private func isolatedDefaults(named name: String) -> UserDefaults {
        let suiteName = "Glassdeck.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "test-suite-name")
        return defaults
    }

    private func suiteName(from defaults: UserDefaults) -> String {
        defaults.string(forKey: "test-suite-name") ?? ""
    }
}

@MainActor
private final class BackgroundRuntimeRecorder {
    var featureEnabledValues: [Bool] = []
    var liveSessionValues: [Bool] = []
    var requestAuthorizationCount = 0
    var resumeCount = 0
}
