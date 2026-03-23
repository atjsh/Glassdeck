import Foundation
import Observation
import os

/// Manages connection profile persistence and state.
@Observable
public final class ConnectionStore {
    private static let logger = Logger(subsystem: "com.glassdeck", category: "ConnectionStore")

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
        do {
            let data = try JSONEncoder().encode(connections)
            defaults.set(data, forKey: storageKey)
        } catch {
            Self.logger.error("Failed to encode connections: \(error.localizedDescription)")
        }
    }

    private func loadConnections() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([ConnectionProfile].self, from: data)
            connections = decoded
        } catch {
            Self.logger.error("Failed to decode connections: \(error.localizedDescription)")
        }
    }
}
