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
}
