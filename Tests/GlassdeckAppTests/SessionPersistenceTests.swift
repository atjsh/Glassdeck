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

    func testSessionPersistenceStoreClearsCorruptedSnapshotData() {
        let suiteName = "Glassdeck.CorruptedSessionPersistenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(Data("not-json".utf8), forKey: "persisted-sessions")
        let store = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )

        XCTAssertNil(store.loadSnapshot())
        XCTAssertNil(defaults.data(forKey: "persisted-sessions"))
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

    func testSessionManagerRestorePersistedSessionsIsIdempotent() {
        let defaults = isolatedDefaults(named: "RestorePersistedSessionIdempotent")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let sessionID = UUID()
        persistenceStore.saveSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: sampleProfile(),
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 4_000),
                        reconnectState: .attempting(attempt: 2, maxAttempts: 5),
                        terminalTitle: "tester@restore-idempotent",
                        terminalSize: TerminalSize(columns: 120, rows: 24),
                        terminalPixelSize: nil,
                        scrollbackLines: 111,
                        shouldRestoreConnectionOnForeground: false,
                        isOnExternalDisplay: false
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: nil
            )
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore
        )

        let initialSessionIDs = sessionManager.sessions.map(\.id)
        let initialActiveSessionID = sessionManager.activeSessionID
        let initialExternalDisplaySessionID = sessionManager.externalDisplaySessionID

        XCTAssertEqual(initialSessionIDs.count, 1)

        sessionManager.restorePersistedSessionsIfNeeded()

        XCTAssertEqual(sessionManager.sessions.map(\.id), initialSessionIDs)
        XCTAssertEqual(sessionManager.activeSessionID, initialActiveSessionID)
        XCTAssertEqual(
            sessionManager.externalDisplaySessionID,
            initialExternalDisplaySessionID
        )

        sessionManager.closeSession(id: sessionID)

        XCTAssertNil(sessionManager.activeSessionID)
        XCTAssertTrue(sessionManager.sessions.isEmpty)

        sessionManager.restorePersistedSessionsIfNeeded()

        XCTAssertTrue(sessionManager.sessions.isEmpty)
        XCTAssertNil(sessionManager.externalDisplaySessionID)
    }

    func testSessionManagerClearsPersistedSnapshotWhenNoSessionsRemain() throws {
        let defaults = isolatedDefaults(named: "PersistedSnapshotClearsOnEmpty")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let sessionID = UUID()

        persistenceStore.saveSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: sampleProfile(),
                        status: .disconnected,
                        connectedAt: nil,
                        reconnectState: .idle,
                        terminalTitle: "clear@session",
                        terminalSize: TerminalSize(columns: 80, rows: 24),
                        terminalPixelSize: nil,
                        scrollbackLines: 0,
                        shouldRestoreConnectionOnForeground: false,
                        isOnExternalDisplay: false
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: nil
            )
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore
        )

        XCTAssertNotNil(persistenceStore.loadSnapshot())

        let restoredSession = try XCTUnwrap(sessionManager.sessions.first)
        sessionManager.closeSession(id: restoredSession.id)

        XCTAssertNil(persistenceStore.loadSnapshot())
    }

    func testSessionManagerMigratesExternalDisplayRoutingFromPersistedSessionFlag() throws {
        let defaults = isolatedDefaults(named: "MigrateExternalDisplayRouting")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let sessionID = UUID()
        let legacyExternalSessionID = UUID()

        persistenceStore.saveSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: sampleProfile(),
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 10_101),
                        reconnectState: .idle,
                        terminalTitle: "legacy@session",
                        terminalSize: TerminalSize(columns: 80, rows: 24),
                        terminalPixelSize: nil,
                        scrollbackLines: 111,
                        shouldRestoreConnectionOnForeground: false,
                        isOnExternalDisplay: false
                    ),
                    PersistedSessionDescriptor(
                        id: legacyExternalSessionID,
                        profile: sampleProfile(),
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 10_102),
                        reconnectState: .idle,
                        terminalTitle: "legacy@ext",
                        terminalSize: TerminalSize(columns: 90, rows: 24),
                        terminalPixelSize: nil,
                        scrollbackLines: 128,
                        shouldRestoreConnectionOnForeground: false,
                        isOnExternalDisplay: true
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: nil
            )
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore
        )

        XCTAssertEqual(sessionManager.externalDisplaySessionID, legacyExternalSessionID)
        XCTAssertEqual(sessionManager.activeSessionID, sessionID)
        XCTAssertTrue(
            try XCTUnwrap(sessionManager.externalDisplaySession).isOnExternalDisplay
        )

        let refreshedSnapshot = try XCTUnwrap(persistenceStore.loadSnapshot())
        XCTAssertEqual(refreshedSnapshot.externalDisplaySessionID, legacyExternalSessionID)
        XCTAssertFalse(
            try XCTUnwrap(
                refreshedSnapshot.sessions.first(where: { $0.id == sessionID })
            ).isOnExternalDisplay
        )
    }

    func testSessionManagerCanPrimeRestoredSessionWithoutPreparingSurface() throws {
        let defaults = isolatedDefaults(named: "PrimeRestoredSessionWithoutSurface")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.PrimeRestoredSessionWithoutSurface.\(UUID().uuidString)"
        )
        let profile = sampleProfile()
        let sessionID = UUID()
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore
        )
        sessionManager.replaceSessionsFromPersistedSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: profile,
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 5_432),
                        reconnectState: .idle,
                        terminalTitle: "\(profile.username)@\(profile.host)",
                        terminalSize: TerminalSize(columns: 80, rows: 24),
                        terminalPixelSize: nil,
                        scrollbackLines: 0,
                        shouldRestoreConnectionOnForeground: true,
                        isOnExternalDisplay: false
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: nil
            ),
            prepareSurfaces: false
        )

        let restoredSession = try XCTUnwrap(sessionManager.activeSession)
        XCTAssertNil(restoredSession.surface)
        XCTAssertFalse(sessionManager.isSessionDetailPresentable(for: restoredSession))

        sessionManager.primeSyntheticPreviewSession(
            restoredSession,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "\(profile.username)@\(profile.host)",
                transcript: """
                \(profile.username)@\(profile.host):~$ ls ~/testdata
                nested
                nano-target.txt
                preview.txt
                """,
                terminalSize: TerminalSize(columns: 100, rows: 30),
                scrollbackLines: 3
            )
        )

        XCTAssertNil(restoredSession.surface)
        XCTAssertTrue(sessionManager.isSessionDetailPresentable(for: restoredSession))
        XCTAssertEqual(restoredSession.status, .reconnecting)
        XCTAssertTrue(restoredSession.shouldRestoreConnectionOnForeground)
        XCTAssertEqual(restoredSession.terminalTitle, "\(profile.username)@\(profile.host)")
        XCTAssertEqual(restoredSession.terminalSize, TerminalSize(columns: 100, rows: 30))
        XCTAssertEqual(restoredSession.scrollbackLines, 3)
        XCTAssertTrue(restoredSession.terminalVisibleTextSummary.contains("preview.txt"))
    }

    func testPrimeSyntheticPreviewSessionCanFreezeConnectedPresentationWithoutRestore() throws {
        let defaults = isolatedDefaults(named: "FreezeSyntheticPreviewPresentation")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.FreezeSyntheticPreviewPresentation.\(UUID().uuidString)"
        )
        let profile = sampleProfile()
        let sessionID = UUID()
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore
        )
        sessionManager.replaceSessionsFromPersistedSnapshot(
            PersistedSessionSnapshot(
                sessions: [
                    PersistedSessionDescriptor(
                        id: sessionID,
                        profile: profile,
                        status: .connected,
                        connectedAt: Date(timeIntervalSince1970: 6_789),
                        reconnectState: .attempting(attempt: 1, maxAttempts: 5),
                        terminalTitle: "\(profile.username)@\(profile.host)",
                        terminalSize: TerminalSize(columns: 80, rows: 24),
                        terminalPixelSize: nil,
                        scrollbackLines: 0,
                        shouldRestoreConnectionOnForeground: true,
                        isOnExternalDisplay: false
                    )
                ],
                activeSessionID: sessionID,
                externalDisplaySessionID: nil
            ),
            prepareSurfaces: false
        )

        let restoredSession = try XCTUnwrap(sessionManager.activeSession)
        XCTAssertEqual(restoredSession.status, .reconnecting)
        XCTAssertTrue(restoredSession.shouldRestoreConnectionOnForeground)

        sessionManager.primeSyntheticPreviewSession(
            restoredSession,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "\(profile.username)@\(profile.host)",
                transcript: """
                \(profile.username)@\(profile.host):~$ echo GLASSDECK_UI_KEY_OK
                GLASSDECK_UI_KEY_OK
                \(profile.username)@\(profile.host):~$ ls ~/testdata
                preview.txt
                """,
                terminalSize: TerminalSize(columns: 90, rows: 28),
                scrollbackLines: 4
            ),
            runtimeMode: .freezeConnectedPresentation
        )

        XCTAssertEqual(restoredSession.status, .connected)
        XCTAssertEqual(restoredSession.reconnectState, .idle)
        XCTAssertFalse(restoredSession.shouldRestoreConnectionOnForeground)
        XCTAssertNil(restoredSession.surface)
        XCTAssertTrue(sessionManager.isSessionDetailPresentable(for: restoredSession))
        XCTAssertTrue(restoredSession.terminalVisibleTextSummary.contains("GLASSDECK_UI_KEY_OK"))
        XCTAssertTrue(restoredSession.terminalVisibleTextSummary.contains("preview.txt"))
    }

    func testPrepareDeferredLiveSSHResumeRoutesActiveSessionCorrectly() {
        let defaults = isolatedDefaults(named: "PrepareDeferredLiveSSHResume")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.PrepareDeferredLiveSSHResume.\(UUID().uuidString)"
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore
        )
        let session = SSHSessionModel(profile: sampleProfile())
        session.status = .reconnecting
        session.shouldRestoreConnectionOnForeground = false
        sessionManager.replaceSessionsForPreview(
            [session],
            activeSessionID: session.id,
            externalDisplaySessionID: nil,
            hasExternalDisplayConnected: false
        )

        UITestLaunchSupport.storeDeferredLiveSSHResumeSessionID(session.id, defaults: defaults)

        let routedSession = UITestLaunchSupport.prepareDeferredLiveSSHResumeIfNeeded(
            sessionManager: sessionManager,
            defaults: defaults
        )

        XCTAssertTrue(routedSession === session)
        XCTAssertTrue(session.shouldRestoreConnectionOnForeground)
        XCTAssertNil(
            defaults.string(forKey: "glassdeck.ui-test.deferred-live-ssh-session-id")
        )
    }

    func testLaunchRoutingStateRoundTripsForPreservedHostBackedFlows() {
        let defaults = isolatedDefaults(named: "LaunchRoutingState")
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
        }

        XCTAssertEqual(
            UITestLaunchSupport.launchRoutingState(defaults: defaults),
            .unavailable
        )

        UITestLaunchSupport.setLaunchRoutingState(
            .waitingForRouteableSession,
            defaults: defaults
        )

        XCTAssertEqual(
            UITestLaunchSupport.launchRoutingState(defaults: defaults),
            .waitingForRouteableSession
        )

        UITestLaunchSupport.clearLaunchRoutingState(defaults: defaults)

        XCTAssertEqual(
            UITestLaunchSupport.launchRoutingState(defaults: defaults),
            .unavailable
        )
    }

    func testConnectSurfacesCredentialPersistenceFailureWithoutBreakingSuccessfulConnection() async throws {
        let defaults = isolatedDefaults(named: "CredentialPersistenceFailure")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = FailingCredentialStore()
        let shellProvider = StubShellSessionProvider()
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore,
            shellProvider: shellProvider
        )

        let connectedSession = await sessionManager.connect(
            to: sampleProfile(authMethod: .password),
            password: "persist-me"
        )
        let session = try XCTUnwrap(connectedSession)

        XCTAssertEqual(session.status, .connected)
        XCTAssertEqual(
            session.runtimeWarningMessage,
            FailingCredentialStore.testError.localizedDescription
        )
        XCTAssertEqual(session.connectionPassword, "persist-me")
    }

    func testConnectPreparesSyntheticSurfacePresentationMetricsForManualLiveSession() async throws {
        let defaults = isolatedDefaults(named: "SyntheticSurfacePresentationMetrics")
        let persistenceStore = SessionPersistenceStore(
            defaults: defaults,
            storageKey: "persisted-sessions"
        )
        let credentialStore = SessionCredentialStore(
            service: "Glassdeck.SyntheticSurfacePresentationMetrics.\(UUID().uuidString)"
        )
        let shellProvider = StubShellSessionProvider()
        defer {
            defaults.removePersistentDomain(forName: suiteName(from: defaults))
            credentialStore.removeAll()
        }

        let sessionManager = SessionManager(
            appSettings: AppSettings(defaults: defaults),
            persistenceStore: persistenceStore,
            credentialStore: credentialStore,
            shellProvider: shellProvider
        )

        let connectedSession = await sessionManager.connect(
            to: sampleProfile(authMethod: .password),
            password: "glassdeck"
        )
        let session = try XCTUnwrap(connectedSession)

        XCTAssertEqual(session.status, .connected)
        XCTAssertNotNil(session.surface)
        let pixelSize = try XCTUnwrap(session.terminalPixelSize)
        XCTAssertGreaterThan(pixelSize.width, 0)
        XCTAssertGreaterThan(pixelSize.height, 0)
        XCTAssertTrue(session.terminalHasRenderedFrame)
        XCTAssertTrue(sessionManager.isTerminalPresentationReady(for: session))
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
        sessionManager.primeSyntheticPreviewSession(
            session,
            seed: SessionManager.SyntheticTerminalSeed(
                title: "tester@example.com",
                transcript: "$ echo ok\nok\n$",
                terminalSize: TerminalSize(columns: 100, rows: 30)
            ),
            runtimeMode: .freezeConnectedPresentation
        )
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

private final class FailingCredentialStore: SessionCredentialStoring {
    static let testError = SessionCredentialStore.CredentialStoreError.storeFailed(errSecInteractionNotAllowed)

    func storePassword(_ password: String, for profileID: UUID) throws {
        throw Self.testError
    }

    func password(for profileID: UUID) -> String? {
        nil
    }

    func deletePassword(for profileID: UUID) throws {}

    func removeAll() {}
}

private actor StubShellSessionProvider: ShellSessionProvider {
    private let shell = StubInteractiveShell()

    func connect(to profile: ConnectionProfile, password: String?) async throws -> UUID {
        UUID()
    }

    func openShell(
        connectionID: UUID,
        configuration: ShellLaunchConfiguration
    ) async throws -> any InteractiveShell {
        shell
    }

    func disconnect(connectionID: UUID) async {}

    func removeConnection(connectionID: UUID) async {}
}

private actor StubInteractiveShell: InteractiveShell {
    nonisolated let output = AsyncThrowingStream<Data, Error> { _ in }

    func write(_ data: Data) async throws {}

    func resize(to size: TerminalSize, pixelSize: TerminalPixelSize?) async throws {}

    func close() async {}
}
