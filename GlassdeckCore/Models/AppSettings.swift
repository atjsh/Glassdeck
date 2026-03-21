import Foundation
import Observation

/// App-wide settings and preferences.
@Observable
public final class AppSettings {
    public static let defaultTerminalConfigStorageKey = "glassdeck.terminal-config"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let terminalConfigStorageKey: String

    public var terminalConfig: TerminalConfiguration {
        didSet {
            saveTerminalConfig()
        }
    }
    public var autoReconnect = true
    public var reconnectDelay: TimeInterval = 3.0
    public var maxReconnectAttempts = 5
    public var hapticFeedback = true
    public var remoteTrackpadLastMode: RemoteControlMode = .cursor

    public init(
        defaults: UserDefaults = .standard,
        terminalConfigStorageKey: String = AppSettings.defaultTerminalConfigStorageKey
    ) {
        self.defaults = defaults
        self.terminalConfigStorageKey = terminalConfigStorageKey
        if let data = defaults.data(forKey: terminalConfigStorageKey),
           let decoded = try? JSONDecoder().decode(TerminalConfiguration.self, from: data) {
            self.terminalConfig = decoded
        } else {
            self.terminalConfig = TerminalConfiguration()
        }
    }

    public func resetTerminalConfig() {
        terminalConfig = TerminalConfiguration()
    }

    private func saveTerminalConfig() {
        guard let data = try? JSONEncoder().encode(terminalConfig) else { return }
        defaults.set(data, forKey: terminalConfigStorageKey)
    }
}
