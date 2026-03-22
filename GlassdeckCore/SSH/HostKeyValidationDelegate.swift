import Foundation
import NIOCore
import NIOSSH
import Crypto

/// Information about a host key mismatch (for future UI use).
public struct HostKeyPromptInfo: Sendable {
    public let host: String
    public let port: Int
    public let fingerprint: String
    public let existingFingerprint: String?
    public let isNewHost: Bool
}

/// Validates SSH host keys using Trust-On-First-Use (TOFU).
///
/// - **New host**: Automatically trusts and stores the fingerprint.
/// - **Known host, same key**: Succeeds immediately.
/// - **Known host, different key**: Rejects (possible MITM attack).
final class HostKeyValidationDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let keyData = serializePublicKey(hostKey)
        let fingerprint = HostKeyVerifier.fingerprint(from: keyData)
        let result = HostKeyVerifier.verify(host: host, port: port, fingerprint: fingerprint)

        switch result {
        case .trusted:
            validationCompletePromise.succeed(())

        case .newHost(let fp):
            HostKeyVerifier.trustHost(host: host, port: port, fingerprint: fp)
            validationCompletePromise.succeed(())

        case .mismatch(let expected, let actual):
            validationCompletePromise.fail(
                HostKeyValidationError.mismatch(
                    host: host,
                    port: port,
                    expected: expected,
                    actual: actual
                )
            )
        }
    }

    private func serializePublicKey(_ key: NIOSSHPublicKey) -> Data {
        let openSSH = String(openSSHPublicKey: key)
        let components = openSSH.split(separator: " ", maxSplits: 1)
        guard components.count == 2,
              let rawBytes = Data(base64Encoded: String(components[1])) else {
            return Data(openSSH.utf8)
        }
        return rawBytes
    }
}

enum HostKeyValidationError: Error, LocalizedError {
    case mismatch(host: String, port: Int, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .mismatch(let host, let port, _, _):
            return "Host key for \(host):\(port) has changed. This could indicate a man-in-the-middle attack. Remove the old key with 'Forget Host' and reconnect if this change is expected."
        }
    }
}
