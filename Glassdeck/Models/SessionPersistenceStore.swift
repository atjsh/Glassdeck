#if canImport(UIKit)
import Foundation
import GlassdeckCore

struct PersistedSessionSnapshot: Codable, Equatable {
    var sessions: [PersistedSessionDescriptor]
    var activeSessionID: UUID?
    var externalDisplaySessionID: UUID?
}

struct PersistedSessionDescriptor: Codable, Equatable, Identifiable {
    enum Status: Codable, Equatable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case reconnecting
        case failed(String)
    }

    let id: UUID
    var profile: ConnectionProfile
    var status: Status
    var connectedAt: Date?
    var reconnectState: PersistedReconnectState
    var terminalTitle: String?
    var terminalSize: TerminalSize
    var terminalPixelSize: TerminalPixelSize?
    var scrollbackLines: Int
    var shouldRestoreConnectionOnForeground: Bool
    var isOnExternalDisplay: Bool
}

enum PersistedReconnectState: Codable, Equatable {
    case idle
    case attempting(attempt: Int, maxAttempts: Int)
    case reconnected
    case gaveUp(attempts: Int)
}

final class SessionPersistenceStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "glassdeck.persisted-sessions"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func loadSnapshot() -> PersistedSessionSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(PersistedSessionSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistedSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
#endif
