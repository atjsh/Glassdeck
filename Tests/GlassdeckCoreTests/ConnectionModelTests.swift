import Foundation
@testable import GlassdeckCore
import XCTest

final class ConnectionProfileTests: XCTestCase {
    func testConnectionProfileCodableRoundTrip() throws {
        let original = ConnectionProfile(
            name: "Prod",
            host: "example.com",
            port: 2222,
            username: "root",
            authMethod: .sshKey,
            sshKeyID: "key-1",
            notes: AttributedString("notes")
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: encoded)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.host, original.host)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.username, original.username)
        XCTAssertEqual(decoded.authMethod, original.authMethod)
        XCTAssertEqual(decoded.sshKeyID, original.sshKeyID)
    }
}

final class ConnectionStoreTests: XCTestCase {
    func testConnectionStorePersistsToCustomUserDefaultsSuite() {
        let suiteName = "Glassdeck.ConnectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ConnectionStore(defaults: defaults, storageKey: "connections")
        let profile = ConnectionProfile(name: "Dev", host: "localhost", username: "me")
        store.add(profile)

        let reloaded = ConnectionStore(defaults: defaults, storageKey: "connections")
        XCTAssertEqual(reloaded.connections.count, 1)
        XCTAssertEqual(reloaded.connections.first?.host, "localhost")
    }
}

final class AppSettingsTests: XCTestCase {
    func testAppSettingsPersistsTerminalConfigurationsIndependently() {
        let suiteName = "Glassdeck.AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(
            defaults: defaults,
            terminalConfigStorageKey: "terminal-config"
        )
        settings.iphoneTerminalConfig = TerminalConfiguration(
            fontSize: 18,
            colorScheme: .defaultLight,
            scrollbackLines: 24_000,
            cursorStyle: .bar,
            cursorBlink: false,
            bellSound: false
        )
        settings.externalMonitorTerminalConfig = TerminalConfiguration(
            fontSize: 24,
            colorScheme: .tokyoNight,
            scrollbackLines: 42_000,
            cursorStyle: .underline,
            cursorBlink: true,
            bellSound: true
        )

        let reloaded = AppSettings(
            defaults: defaults,
            terminalConfigStorageKey: "terminal-config"
        )
        XCTAssertEqual(reloaded.iphoneTerminalConfig.fontSize, 18)
        XCTAssertEqual(reloaded.iphoneTerminalConfig.colorScheme, .defaultLight)
        XCTAssertEqual(reloaded.iphoneTerminalConfig.scrollbackLines, 24_000)
        XCTAssertEqual(reloaded.iphoneTerminalConfig.cursorStyle, .bar)
        XCTAssertFalse(reloaded.iphoneTerminalConfig.cursorBlink)
        XCTAssertFalse(reloaded.iphoneTerminalConfig.bellSound)
        XCTAssertEqual(reloaded.externalMonitorTerminalConfig.fontSize, 24)
        XCTAssertEqual(reloaded.externalMonitorTerminalConfig.colorScheme, .tokyoNight)
        XCTAssertEqual(reloaded.externalMonitorTerminalConfig.scrollbackLines, 42_000)
        XCTAssertEqual(reloaded.externalMonitorTerminalConfig.cursorStyle, .underline)
        XCTAssertTrue(reloaded.externalMonitorTerminalConfig.cursorBlink)
        XCTAssertTrue(reloaded.externalMonitorTerminalConfig.bellSound)
        XCTAssertEqual(reloaded.terminalConfig, reloaded.iphoneTerminalConfig)
    }

    func testAppSettingsMigratesLegacyTerminalConfigurationIntoDisplayProfiles() throws {
        let suiteName = "Glassdeck.AppSettingsMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyConfiguration = TerminalConfiguration(
            fontSize: 18,
            colorScheme: .defaultLight,
            scrollbackLines: 24_000,
            cursorStyle: .bar,
            cursorBlink: false,
            bellSound: false
        )
        defaults.set(
            try JSONEncoder().encode(legacyConfiguration),
            forKey: "terminal-config"
        )

        let settings = AppSettings(
            defaults: defaults,
            terminalConfigStorageKey: "terminal-config"
        )

        XCTAssertEqual(settings.iphoneTerminalConfig, legacyConfiguration)
        XCTAssertEqual(settings.externalMonitorTerminalConfig.colorScheme, .defaultLight)
        XCTAssertEqual(settings.externalMonitorTerminalConfig.scrollbackLines, 24_000)
        XCTAssertEqual(settings.externalMonitorTerminalConfig.cursorStyle, .bar)
        XCTAssertFalse(settings.externalMonitorTerminalConfig.cursorBlink)
        XCTAssertFalse(settings.externalMonitorTerminalConfig.bellSound)
        XCTAssertEqual(
            settings.externalMonitorTerminalConfig.fontSize,
            max(legacyConfiguration.fontSize * 1.35, legacyConfiguration.fontSize + 4),
            accuracy: 0.001
        )
        XCTAssertNotNil(defaults.data(forKey: "terminal-config.iphone"))
        XCTAssertNotNil(defaults.data(forKey: "terminal-config.external-monitor"))
    }

    func testAppSettingsPersistsReconnectAndBackgroundPreferences() {
        let suiteName = "Glassdeck.AppSettingsReconnectTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(defaults: defaults)
        settings.autoReconnect = false
        settings.reconnectDelay = 1.5
        settings.maxReconnectAttempts = 9
        settings.hapticFeedback = false
        settings.remoteTrackpadLastMode = .mouse
        settings.backgroundPersistenceEnabled = true

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.autoReconnect)
        XCTAssertEqual(reloaded.reconnectDelay, 1.5, accuracy: 0.001)
        XCTAssertEqual(reloaded.maxReconnectAttempts, 9)
        XCTAssertFalse(reloaded.hapticFeedback)
        XCTAssertEqual(reloaded.remoteTrackpadLastMode, .mouse)
        XCTAssertTrue(reloaded.backgroundPersistenceEnabled)
    }

}

final class TerminalConfigurationTests: XCTestCase {
    func testTerminalConfigurationCodableRoundTrip() throws {
        let original = TerminalConfiguration(
            fontFamily: "JetBrains Mono",
            fontSize: 16,
            colorScheme: .tokyoNight,
            scrollbackLines: 20_000,
            cursorStyle: .underline,
            cursorBlink: false,
            bellSound: false
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalConfiguration.self, from: encoded)

        XCTAssertEqual(decoded.fontFamily, original.fontFamily)
        XCTAssertEqual(decoded.fontSize, original.fontSize)
        XCTAssertEqual(decoded.colorScheme, .tokyoNight)
        XCTAssertEqual(decoded.scrollbackLines, 20_000)
        XCTAssertEqual(decoded.cursorStyle, .underline)
        XCTAssertFalse(decoded.cursorBlink)
        XCTAssertFalse(decoded.bellSound)
        XCTAssertEqual(TerminalColorScheme.tokyoNight.backgroundColor.r, 26)
    }

    func testDefaultLightThemeProvidesLightProjectionPalette() {
        let theme = TerminalColorScheme.defaultLight.theme

        XCTAssertEqual(theme.background, GhosttyVTColor(r: 255, g: 255, b: 255))
        XCTAssertEqual(theme.foreground, GhosttyVTColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(theme.cursor, GhosttyVTColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(theme.palette.count, 256)
        XCTAssertEqual(theme.palette[0], GhosttyVTColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(theme.palette[9], GhosttyVTColor(r: 241, g: 76, b: 76))
    }

    func testTokyoNightThemeProvidesCustomAnsiPalette() {
        let theme = TerminalColorScheme.tokyoNight.theme

        XCTAssertEqual(theme.background, GhosttyVTColor(r: 26, g: 27, b: 38))
        XCTAssertEqual(theme.foreground, GhosttyVTColor(r: 169, g: 177, b: 214))
        XCTAssertEqual(theme.cursor, GhosttyVTColor(r: 192, g: 202, b: 245))
        XCTAssertEqual(theme.palette.count, 256)
        XCTAssertEqual(theme.palette[1], GhosttyVTColor(r: 247, g: 118, b: 142))
        XCTAssertEqual(theme.palette[4], GhosttyVTColor(r: 122, g: 162, b: 247))
    }
}
