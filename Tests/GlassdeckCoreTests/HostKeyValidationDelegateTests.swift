import Crypto
import Foundation
@testable import GlassdeckCore
import NIOCore
import NIOEmbedded
import NIOSSH
import XCTest

final class HostKeyValidationDelegateTests: XCTestCase {
    private var testHost: String!
    private let testPort = 22

    override func setUp() {
        super.setUp()
        testHost = "delegate-test-\(UUID().uuidString)"
    }

    override func tearDown() {
        HostKeyVerifier.forgetHost(host: testHost, port: testPort)
        super.tearDown()
    }

    // MARK: - Tests

    func testDelegateSucceedsForTrustedHost() throws {
        let nioKey = try makeTestPublicKey()
        let fingerprint = HostKeyVerifier.fingerprint(from: publicKeyBytes(nioKey))

        HostKeyVerifier.trustHost(host: testHost, port: testPort, fingerprint: fingerprint)

        let delegate = HostKeyValidationDelegate(
            host: testHost,
            port: testPort,
            promptHandler: { _ in
                XCTFail("Prompt should not be called for a trusted host")
                return false
            }
        )

        let loop = EmbeddedEventLoop()
        defer { try? loop.syncShutdownGracefully() }
        let promise = loop.makePromise(of: Void.self)

        delegate.validateHostKey(hostKey: nioKey, validationCompletePromise: promise)
        loop.run()

        XCTAssertNoThrow(try promise.futureResult.wait())
    }

    func testDelegatePromptsForNewHostAndAccepts() throws {
        let nioKey = try makeTestPublicKey()
        let host = testHost!

        let promptExpectation = expectation(description: "prompt called")
        let delegate = HostKeyValidationDelegate(
            host: host,
            port: testPort,
            promptHandler: { info in
                XCTAssertEqual(info.host, host)
                XCTAssertTrue(info.isNewHost)
                XCTAssertNil(info.existingFingerprint)
                promptExpectation.fulfill()
                return true
            }
        )

        let loop = EmbeddedEventLoop()
        defer { try? loop.syncShutdownGracefully() }
        let promise = loop.makePromise(of: Void.self)

        delegate.validateHostKey(hostKey: nioKey, validationCompletePromise: promise)
        loop.run()

        wait(for: [promptExpectation], timeout: 5)
        XCTAssertNoThrow(try promise.futureResult.wait())

        // Host should now be trusted
        let fingerprint = HostKeyVerifier.fingerprint(from: publicKeyBytes(nioKey))
        switch HostKeyVerifier.verify(host: host, port: testPort, fingerprint: fingerprint) {
        case .trusted:
            break
        default:
            XCTFail("Host should be trusted after acceptance")
        }
    }

    func testDelegatePromptsForNewHostAndRejects() throws {
        let nioKey = try makeTestPublicKey()

        let delegate = HostKeyValidationDelegate(
            host: testHost,
            port: testPort,
            promptHandler: { _ in false }
        )

        let loop = EmbeddedEventLoop()
        defer { try? loop.syncShutdownGracefully() }
        let promise = loop.makePromise(of: Void.self)

        delegate.validateHostKey(hostKey: nioKey, validationCompletePromise: promise)
        loop.run()

        XCTAssertThrowsError(try promise.futureResult.wait()) { error in
            XCTAssertTrue(error is HostKeyValidationError)
        }
    }

    func testDelegateMismatchPromptsWithExistingFingerprint() throws {
        let oldNIOKey = try makeTestPublicKey()
        let oldFingerprint = HostKeyVerifier.fingerprint(from: publicKeyBytes(oldNIOKey))

        HostKeyVerifier.trustHost(host: testHost, port: testPort, fingerprint: oldFingerprint)

        let newNIOKey = try makeTestPublicKey()

        let promptExpectation = expectation(description: "mismatch prompt called")
        let delegate = HostKeyValidationDelegate(
            host: testHost,
            port: testPort,
            promptHandler: { info in
                XCTAssertFalse(info.isNewHost)
                XCTAssertNotNil(info.existingFingerprint)
                XCTAssertEqual(info.existingFingerprint, oldFingerprint)
                promptExpectation.fulfill()
                return true
            }
        )

        let loop = EmbeddedEventLoop()
        defer { try? loop.syncShutdownGracefully() }
        let promise = loop.makePromise(of: Void.self)

        delegate.validateHostKey(hostKey: newNIOKey, validationCompletePromise: promise)
        loop.run()

        wait(for: [promptExpectation], timeout: 5)
        XCTAssertNoThrow(try promise.futureResult.wait())
    }

    // MARK: - Helpers

    private func makeTestPublicKey() throws -> NIOSSHPublicKey {
        let privateKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let openSSH = String(openSSHPublicKey: privateKey.publicKey)
        return try NIOSSHPublicKey(openSSHPublicKey: openSSH)
    }

    private func publicKeyBytes(_ key: NIOSSHPublicKey) -> Data {
        let openSSH = String(openSSHPublicKey: key)
        let components = openSSH.split(separator: " ", maxSplits: 1)
        guard components.count == 2,
              let rawBytes = Data(base64Encoded: String(components[1])) else {
            return Data(openSSH.utf8)
        }
        return rawBytes
    }
}
