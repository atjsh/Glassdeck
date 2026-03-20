import Foundation

/// Manages connection profile persistence and state.
@Observable
final class ConnectionStore {
    private(set) var connections: [ConnectionProfile] = []

    init() {
        loadConnections()
    }

    func add(_ profile: ConnectionProfile) {
        connections.append(profile)
        saveConnections()
    }

    func update(_ profile: ConnectionProfile) {
        if let index = connections.firstIndex(where: { $0.id == profile.id }) {
            connections[index] = profile
            saveConnections()
        }
    }

    func delete(_ profile: ConnectionProfile) {
        connections.removeAll { $0.id == profile.id }
        saveConnections()
    }

    // MARK: - Persistence (UserDefaults for now; SwiftData in Xcode 26 build)

    private let storageKey = "glassdeck.connections"

    private func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) else {
            return
        }
        connections = decoded
    }
}
