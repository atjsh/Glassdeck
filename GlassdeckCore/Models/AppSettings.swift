import Foundation
import Observation

/// App-wide settings and preferences.
@Observable
public final class AppSettings {
    public static let defaultTerminalConfigStorageKey = "glassdeck.terminal-config"
    public static let defaultIPhoneTerminalConfigStorageKey = "\(defaultTerminalConfigStorageKey).iphone"
    public static let defaultExternalMonitorTerminalConfigStorageKey = "\(defaultTerminalConfigStorageKey).external-monitor"
    public static let defaultAutoReconnectStorageKey = "glassdeck.auto-reconnect"
    public static let defaultReconnectDelayStorageKey = "glassdeck.reconnect-delay"
    public static let defaultMaxReconnectAttemptsStorageKey = "glassdeck.max-reconnect-attempts"
    public static let defaultHapticFeedbackStorageKey = "glassdeck.haptic-feedback"
    public static let defaultRemoteTrackpadModeStorageKey = "glassdeck.remote-trackpad-mode"
    public static let defaultBackgroundPersistenceEnabledStorageKey = "glassdeck.background-persistence-enabled"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let iphoneTerminalConfigStorageKey: String
    @ObservationIgnored private let externalMonitorTerminalConfigStorageKey: String
    @ObservationIgnored private let autoReconnectStorageKey: String
    @ObservationIgnored private let reconnectDelayStorageKey: String
    @ObservationIgnored private let maxReconnectAttemptsStorageKey: String
    @ObservationIgnored private let hapticFeedbackStorageKey: String
    @ObservationIgnored private let remoteTrackpadModeStorageKey: String
    @ObservationIgnored private let backgroundPersistenceEnabledStorageKey: String

    public var iphoneTerminalConfig: TerminalConfiguration {
        didSet {
            saveTerminalConfig(iphoneTerminalConfig, forKey: iphoneTerminalConfigStorageKey)
        }
    }
    public var externalMonitorTerminalConfig: TerminalConfiguration {
        didSet {
            saveTerminalConfig(
                externalMonitorTerminalConfig,
                forKey: externalMonitorTerminalConfigStorageKey
            )
        }
    }
    public var terminalConfig: TerminalConfiguration {
        get { iphoneTerminalConfig }
        set { iphoneTerminalConfig = newValue }
    }
    public var autoReconnect: Bool {
        didSet {
            defaults.set(autoReconnect, forKey: autoReconnectStorageKey)
        }
    }
    public var reconnectDelay: TimeInterval {
        didSet {
            defaults.set(reconnectDelay, forKey: reconnectDelayStorageKey)
        }
    }
    public var maxReconnectAttempts: Int {
        didSet {
            defaults.set(maxReconnectAttempts, forKey: maxReconnectAttemptsStorageKey)
        }
    }
    public var hapticFeedback: Bool {
        didSet {
            defaults.set(hapticFeedback, forKey: hapticFeedbackStorageKey)
        }
    }
    public var remoteTrackpadLastMode: RemoteControlMode {
        didSet {
            defaults.set(remoteTrackpadLastMode.rawValue, forKey: remoteTrackpadModeStorageKey)
        }
    }
    public var backgroundPersistenceEnabled: Bool {
        didSet {
            defaults.set(backgroundPersistenceEnabled, forKey: backgroundPersistenceEnabledStorageKey)
        }
    }

    public init(
        defaults: UserDefaults = .standard,
        terminalConfigStorageKey: String = AppSettings.defaultTerminalConfigStorageKey,
        iphoneTerminalConfigStorageKey: String? = nil,
        externalMonitorTerminalConfigStorageKey: String? = nil,
        autoReconnectStorageKey: String = AppSettings.defaultAutoReconnectStorageKey,
        reconnectDelayStorageKey: String = AppSettings.defaultReconnectDelayStorageKey,
        maxReconnectAttemptsStorageKey: String = AppSettings.defaultMaxReconnectAttemptsStorageKey,
        hapticFeedbackStorageKey: String = AppSettings.defaultHapticFeedbackStorageKey,
        remoteTrackpadModeStorageKey: String = AppSettings.defaultRemoteTrackpadModeStorageKey,
        backgroundPersistenceEnabledStorageKey: String = AppSettings.defaultBackgroundPersistenceEnabledStorageKey
    ) {
        self.defaults = defaults
        self.iphoneTerminalConfigStorageKey =
            iphoneTerminalConfigStorageKey
            ?? "\(terminalConfigStorageKey).iphone"
        self.externalMonitorTerminalConfigStorageKey =
            externalMonitorTerminalConfigStorageKey
            ?? "\(terminalConfigStorageKey).external-monitor"
        self.autoReconnectStorageKey = autoReconnectStorageKey
        self.reconnectDelayStorageKey = reconnectDelayStorageKey
        self.maxReconnectAttemptsStorageKey = maxReconnectAttemptsStorageKey
        self.hapticFeedbackStorageKey = hapticFeedbackStorageKey
        self.remoteTrackpadModeStorageKey = remoteTrackpadModeStorageKey
        self.backgroundPersistenceEnabledStorageKey = backgroundPersistenceEnabledStorageKey
        let legacyTerminalConfig = Self.loadTerminalConfig(
            from: defaults,
            forKey: terminalConfigStorageKey
        )
        let persistedIPhoneTerminalConfig = Self.loadTerminalConfig(
            from: defaults,
            forKey: self.iphoneTerminalConfigStorageKey
        )
        let persistedExternalMonitorTerminalConfig = Self.loadTerminalConfig(
            from: defaults,
            forKey: self.externalMonitorTerminalConfigStorageKey
        )

        let resolvedIPhoneTerminalConfig =
            persistedIPhoneTerminalConfig
            ?? legacyTerminalConfig
            ?? TerminalConfiguration()
        self.iphoneTerminalConfig = resolvedIPhoneTerminalConfig
        self.externalMonitorTerminalConfig =
            persistedExternalMonitorTerminalConfig
            ?? legacyTerminalConfig.map(Self.migratedExternalMonitorConfiguration(from:))
            ?? Self.migratedExternalMonitorConfiguration(from: resolvedIPhoneTerminalConfig)
        self.autoReconnect =
            defaults.object(forKey: autoReconnectStorageKey) as? Bool
            ?? true
        self.reconnectDelay =
            defaults.object(forKey: reconnectDelayStorageKey) as? Double
            ?? 3.0
        self.maxReconnectAttempts =
            defaults.object(forKey: maxReconnectAttemptsStorageKey) as? Int
            ?? 5
        self.hapticFeedback =
            defaults.object(forKey: hapticFeedbackStorageKey) as? Bool
            ?? true
        self.remoteTrackpadLastMode =
            defaults.string(forKey: remoteTrackpadModeStorageKey)
            .flatMap(RemoteControlMode.init(rawValue:))
            ?? .cursor
        self.backgroundPersistenceEnabled =
            defaults.object(forKey: backgroundPersistenceEnabledStorageKey) as? Bool
            ?? false

        if persistedIPhoneTerminalConfig == nil {
            saveTerminalConfig(iphoneTerminalConfig, forKey: self.iphoneTerminalConfigStorageKey)
        }
        if persistedExternalMonitorTerminalConfig == nil {
            saveTerminalConfig(
                externalMonitorTerminalConfig,
                forKey: self.externalMonitorTerminalConfigStorageKey
            )
        }
    }

    public func resetTerminalConfig() {
        iphoneTerminalConfig = TerminalConfiguration()
        externalMonitorTerminalConfig = Self.defaultExternalMonitorTerminalConfiguration()
    }

    public func terminalConfig(for target: TerminalDisplayTarget) -> TerminalConfiguration {
        switch target {
        case .iphone:
            iphoneTerminalConfig
        case .externalMonitor:
            externalMonitorTerminalConfig
        }
    }

    public func setTerminalConfig(_ configuration: TerminalConfiguration, for target: TerminalDisplayTarget) {
        switch target {
        case .iphone:
            iphoneTerminalConfig = configuration
        case .externalMonitor:
            externalMonitorTerminalConfig = configuration
        }
    }

    private func saveTerminalConfig(_ configuration: TerminalConfiguration, forKey key: String) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadTerminalConfig(
        from defaults: UserDefaults,
        forKey key: String
    ) -> TerminalConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TerminalConfiguration.self, from: data)
    }

    private static func defaultExternalMonitorTerminalConfiguration() -> TerminalConfiguration {
        migratedExternalMonitorConfiguration(from: TerminalConfiguration())
    }

    private static func migratedExternalMonitorConfiguration(
        from configuration: TerminalConfiguration
    ) -> TerminalConfiguration {
        var migratedConfiguration = configuration
        migratedConfiguration.fontSize = max(
            configuration.fontSize * 1.35,
            configuration.fontSize + 4
        )
        return migratedConfiguration
    }
}
