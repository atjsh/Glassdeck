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
    func testAppSettingsPersistsTerminalConfiguration() {
        let suiteName = "Glassdeck.AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(
            defaults: defaults,
            terminalConfigStorageKey: "terminal-config"
        )
        settings.terminalConfig = TerminalConfiguration(
            fontSize: 18,
            colorScheme: .defaultLight,
            scrollbackLines: 24_000,
            cursorStyle: .bar,
            cursorBlink: false,
            bellSound: false
        )

        let reloaded = AppSettings(
            defaults: defaults,
            terminalConfigStorageKey: "terminal-config"
        )
        XCTAssertEqual(reloaded.terminalConfig.fontSize, 18)
        XCTAssertEqual(reloaded.terminalConfig.colorScheme, .defaultLight)
        XCTAssertEqual(reloaded.terminalConfig.scrollbackLines, 24_000)
        XCTAssertEqual(reloaded.terminalConfig.cursorStyle, .bar)
        XCTAssertFalse(reloaded.terminalConfig.cursorBlink)
        XCTAssertFalse(reloaded.terminalConfig.bellSound)
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
