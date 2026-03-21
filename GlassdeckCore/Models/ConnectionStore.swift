import Foundation
import Observation

/// Manages connection profile persistence and state.
@Observable
public final class ConnectionStore {
    public private(set) var connections: [ConnectionProfile] = []
    private let defaults: UserDefaults

    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "glassdeck.connections"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        loadConnections()
    }

    public func add(_ profile: ConnectionProfile) {
        connections.append(profile)
        saveConnections()
    }

    public func update(_ profile: ConnectionProfile) {
        if let index = connections.firstIndex(where: { $0.id == profile.id }) {
            connections[index] = profile
            saveConnections()
        }
    }

    public func replaceAll(with profiles: [ConnectionProfile]) {
        connections = profiles
        saveConnections()
    }

    public func recordConnection(id: UUID, at date: Date = .now) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].lastConnected = date
        saveConnections()
    }

    public func delete(_ profile: ConnectionProfile) {
        connections.removeAll { $0.id == profile.id }
        saveConnections()
    }

    // MARK: - Persistence (UserDefaults for now; SwiftData in Xcode 26 build)

    private func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func loadConnections() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) else {
            return
        }
        connections = decoded
    }
}
