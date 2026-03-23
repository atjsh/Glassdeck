import XCTest
@testable import GlassdeckBuildCore

final class SSHSmokeClientTests: XCTestCase {
    func testOpenSSHParserLoadsFixtureKey() throws {
        let pem = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACD67CxchJSsuFSG809MzmmeGCw1GZtTxYxCEjopHWJp8wAAALAclZg4HJWY
        OAAAAAtzc2gtZWQyNTUxOQAAACD67CxchJSsuFSG809MzmmeGCw1GZtTxYxCEjopHWJp8w
        AAAEA0gzlBCKzSArLActBBkkI9fS2Hzd2DZJrPPVto6hxASvrsLFyElKy4VIbzT0zOaZ4Y
        LDUZm1PFjEISOikdYmnzAAAALGplb25zZW9uZ2h1bkBqZW9uc2VvbmdodW5zLU1hY0Jvb2
        stUHJvLmxvY2FsAQ==
        -----END OPENSSH PRIVATE KEY-----
        """

        let privateKey = try OpenSSHEd25519PrivateKeyParser.parse(pem: pem)

        XCTAssertEqual(
            String(openSSHPublicKey: privateKey.publicKey),
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPrsLFyElKy4VIbzT0zOaZ4YLDUZm1PFjEISOikdYmnz"
        )
    }
}
