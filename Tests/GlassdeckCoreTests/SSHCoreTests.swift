import Foundation
@testable import GlassdeckCore
import XCTest

final class HostKeyVerifierTests: XCTestCase {
    func testHostKeyVerifierTrustMismatchAndForget() {
        let host = "glassdeck-test-\(UUID().uuidString)"
        let port = 22
        let fingerprint = "SHA256:aa:bb"
        let mismatch = "SHA256:cc:dd"

        switch HostKeyVerifier.verify(host: host, port: port, fingerprint: fingerprint) {
        case .newHost(let value):
            XCTAssertEqual(value, fingerprint)
        default:
            XCTFail("Expected first-use host state")
        }

        HostKeyVerifier.trustHost(host: host, port: port, fingerprint: fingerprint)
        switch HostKeyVerifier.verify(host: host, port: port, fingerprint: fingerprint) {
        case .trusted:
            break
        default:
            XCTFail("Expected trusted host after recording fingerprint")
        }

        switch HostKeyVerifier.verify(host: host, port: port, fingerprint: mismatch) {
        case .mismatch(let expected, let actual):
            XCTAssertEqual(expected, fingerprint)
            XCTAssertEqual(actual, mismatch)
        default:
            XCTFail("Expected mismatch after trusting host")
        }

        HostKeyVerifier.forgetHost(host: host, port: port)
        switch HostKeyVerifier.verify(host: host, port: port, fingerprint: fingerprint) {
        case .newHost:
            break
        default:
            XCTFail("Expected host removal to reset verification state")
        }
    }
}

final class SSHAuthenticatorTests: XCTestCase {
    func testGenerateEd25519KeyProducesParseableAuthorizedKey() throws {
        let keypair = SSHAuthenticator.generateEd25519Key()
        XCTAssertEqual(keypair.privateKeyData.count, 32)

        let publicKey = try parsePublicKeyPrefix(keypair.publicKey)
        XCTAssertTrue(publicKey.hasPrefix("ssh-ed25519 "))
    }

    func testParseEd25519OpenSSHFixture() throws {
        let generated = try SSHAuthenticator.publicKeyString(fromPrivateKeyData: Data(SSHFixture.ed25519PrivateKey.utf8))
        XCTAssertEqual(normalizedPublicKey(generated), normalizedPublicKey(SSHFixture.ed25519PublicKey))
    }

    func testParseP256OpenSSHFixture() throws {
        let generated = try SSHAuthenticator.publicKeyString(fromPrivateKeyData: Data(SSHFixture.p256PrivateKey.utf8))
        XCTAssertEqual(normalizedPublicKey(generated), normalizedPublicKey(SSHFixture.p256PublicKey))
    }

    func testRejectsMalformedPEM() {
        XCTAssertThrowsError(
            try SSHAuthenticator.publicKeyString(
                fromPrivateKeyData: Data("-----BEGIN OPENSSH PRIVATE KEY-----\ninvalid\n-----END OPENSSH PRIVATE KEY-----".utf8)
            )
        )
    }

    private func parsePublicKeyPrefix(_ publicKey: String) throws -> String {
        let parts = publicKey.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        return parts.prefix(2).joined(separator: " ")
    }

    private func normalizedPublicKey(_ key: String) -> String {
        key.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            .prefix(2)
            .joined(separator: " ")
    }
}

final class SSHKeyImportValidatorTests: XCTestCase {
    func testPreviewNormalizesPEMAndGeneratesName() throws {
        let preview = try SSHKeyImportValidator.preview(
            privateKeyData: Data(("\n" + SSHFixture.ed25519PrivateKey + "\n").utf8)
        )

        XCTAssertEqual(
            preview.publicKey.split(separator: " ").prefix(2).joined(separator: " "),
            SSHFixture.ed25519PublicKey.split(separator: " ").prefix(2).joined(separator: " ")
        )
        XCTAssertTrue(preview.name.hasPrefix("ssh-ed25519-"))
    }

    func testPreviewRejectsMalformedClipboardText() {
        XCTAssertThrowsError(
            try SSHKeyImportValidator.preview(privateKeyText: "not-a-private-key")
        )
    }
}

enum SSHFixture {
    static let ed25519PrivateKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACD67CxchJSsuFSG809MzmmeGCw1GZtTxYxCEjopHWJp8wAAALAclZg4HJWY
    OAAAAAtzc2gtZWQyNTUxOQAAACD67CxchJSsuFSG809MzmmeGCw1GZtTxYxCEjopHWJp8w
    AAAEA0gzlBCKzSArLActBBkkI9fS2Hzd2DZJrPPVto6hxASvrsLFyElKy4VIbzT0zOaZ4Y
    LDUZm1PFjEISOikdYmnzAAAALGplb25zZW9uZ2h1bkBqZW9uc2VvbmdodW5zLU1hY0Jvb2
    stUHJvLmxvY2FsAQ==
    -----END OPENSSH PRIVATE KEY-----
    """

    static let ed25519PublicKey = """
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPrsLFyElKy4VIbzT0zOaZ4YLDUZm1PFjEISOikdYmnz jeonseonghun@jeonseonghuns-MacBook-Pro.local
    """

    static let p256PrivateKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQQtlDoA1JTITnizLH4IPgmRZbrkzykL
    SjlBb0V4jHBindScEzHBPAeSBE7++lx0Se7vSI1x4cO9fr9AS0rfj1+CAAAAyMWegrfFno
    K3AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC2UOgDUlMhOeLMs
    fgg+CZFluuTPKQtKOUFvRXiMcGKd1JwTMcE8B5IETv76XHRJ7u9IjXHhw71+v0BLSt+PX4
    IAAAAhAOXvzYAh5TIao8u3A0cfclfb5+/hmsIAlMscgpr+0mFMAAAALGplb25zZW9uZ2h1
    bkBqZW9uc2VvbmdodW5zLU1hY0Jvb2stUHJvLmxvY2FsAQID
    -----END OPENSSH PRIVATE KEY-----
    """

    static let p256PublicKey = """
    ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC2UOgDUlMhOeLMsfgg+CZFluuTPKQtKOUFvRXiMcGKd1JwTMcE8B5IETv76XHRJ7u9IjXHhw71+v0BLSt+PX4I= jeonseonghun@jeonseonghuns-MacBook-Pro.local
    """
}
