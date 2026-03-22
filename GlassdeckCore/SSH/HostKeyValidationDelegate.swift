import Foundation
import NIOCore
import NIOSSH
import Crypto

/// Information presented to the user when a host key needs verification.
public struct HostKeyPromptInfo: Sendable {
    public let host: String
    public let port: Int
    public let fingerprint: String
    public let existingFingerprint: String?
    public let isNewHost: Bool
}

/// Bridges the NIO SSH host-key validation callback to the existing
/// ``HostKeyVerifier`` TOFU store, prompting the user via an async closure
/// when the key is new or has changed.
final class HostKeyValidationDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let promptHandler: @Sendable (HostKeyPromptInfo) async -> Bool

    init(
        host: String,
        port: Int,
        promptHandler: @escaping @Sendable (HostKeyPromptInfo) async -> Bool
    ) {
        self.host = host
        self.port = port
        self.promptHandler = promptHandler
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
            let info = HostKeyPromptInfo(
                host: host,
                port: port,
                fingerprint: fp,
                existingFingerprint: nil,
                isNewHost: true
            )
            bridgeToAsync(promise: validationCompletePromise, fingerprint: fp, info: info)

        case .mismatch(let expected, let actual):
            let info = HostKeyPromptInfo(
                host: host,
                port: port,
                fingerprint: actual,
                existingFingerprint: expected,
                isNewHost: false
            )
            bridgeToAsync(promise: validationCompletePromise, fingerprint: actual, info: info)
        }
    }

    private func bridgeToAsync(
        promise: EventLoopPromise<Void>,
        fingerprint: String,
        info: HostKeyPromptInfo
    ) {
        let host = self.host
        let port = self.port
        let handler = self.promptHandler

        promise.completeWithTask {
            let accepted = await handler(info)
            guard accepted else {
                throw HostKeyValidationError.rejected
            }
            HostKeyVerifier.trustHost(host: host, port: port, fingerprint: fingerprint)
        }
    }

    private func serializePublicKey(_ key: NIOSSHPublicKey) -> Data {
        // Convert to "algorithm base64key" format, extract the base64 portion, decode raw bytes
        let openSSH = String(openSSHPublicKey: key)
        let components = openSSH.split(separator: " ", maxSplits: 1)
        guard components.count == 2,
              let rawBytes = Data(base64Encoded: String(components[1])) else {
            // Fallback: hash the full OpenSSH string representation
            return Data(openSSH.utf8)
        }
        return rawBytes
    }
}

enum HostKeyValidationError: Error, LocalizedError {
    case rejected

    var errorDescription: String? {
        "Host key verification was rejected by the user."
    }
}
