import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public enum SSHSmokeClientError: Error, LocalizedError {
    case unsupportedPrivateKey(String)
    case invalidOpenSSHKey(String)
    case invalidKeyType(String)
    case invalidChannelType
    case execRequestRejected
    case authenticationFailed
    case commandOutputMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedPrivateKey(path):
            return "Only unencrypted OpenSSH ed25519 private keys are supported for smoke tests: \(path)"
        case let .invalidOpenSSHKey(message):
            return "Invalid OpenSSH private key: \(message)"
        case let .invalidKeyType(keyType):
            return "Unsupported SSH private key type: \(keyType)"
        case .invalidChannelType:
            return "SSH server returned an unexpected channel type."
        case .execRequestRejected:
            return "SSH exec request was rejected by the server."
        case .authenticationFailed:
            return "SSH authentication did not succeed."
        case let .commandOutputMismatch(expected, actual):
            return "Expected '\(expected)' in SSH output, got: \(actual)"
        }
    }
}

public final class SSHSmokeClient: Sendable {
    public init() {}

    public func run(_ scenario: SSHSmokeScenario) async throws -> SSHSmokeResult {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let authDelegate = try makeAuthDelegate(for: scenario)
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                let ssh = NIOSSHHandler(
                    role: .client(
                        .init(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: AcceptAllHostKeysDelegate()
                        )
                    ),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                return channel.pipeline.addHandlers([ssh, RootSSHErrorHandler()])
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

        var rootChannel: Channel?
        var sshChildChannel: Channel?

        do {
            let channel = try await bootstrap.connect(host: scenario.host, port: scenario.port).get()
            rootChannel = channel

            let sshHandler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
            let resultPromise = channel.eventLoop.makePromise(of: SSHSmokeResult.self)
            let childChannelPromise = channel.eventLoop.makePromise(of: Channel.self)

            sshHandler.createChannel(childChannelPromise, channelType: .session) { childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(SSHSmokeClientError.invalidChannelType)
                }

                return childChannel.eventLoop.makeCompletedFuture {
                    let sync = childChannel.pipeline.syncOperations
                    try sync.addHandler(SSHExecCaptureHandler(scenario: scenario, resultPromise: resultPromise))
                    try sync.addHandler(RootSSHErrorHandler())
                }
            }

            let childChannel = try await childChannelPromise.futureResult.get()
            sshChildChannel = childChannel

            let result = try await resultPromise.futureResult.get()
            if !result.standardOutput.contains(scenario.expectedSubstring) {
                throw SSHSmokeClientError.commandOutputMismatch(
                    expected: scenario.expectedSubstring,
                    actual: result.standardOutput
                )
            }

            try? await childChannel.close().get()
            try? await channel.close().get()
            try await shutdown(group)
            return result
        } catch {
            if let sshChildChannel {
                try? await sshChildChannel.close().get()
            }
            if let rootChannel {
                try? await rootChannel.close().get()
            }
            try? await shutdown(group)
            throw error
        }
    }

    private func makeAuthDelegate(for scenario: SSHSmokeScenario) throws -> NIOSSHClientUserAuthenticationDelegate {
        switch scenario.authentication {
        case let .password(password):
            return SimplePasswordDelegate(username: scenario.username, password: password)
        case let .privateKey(path):
            let privateKey = try OpenSSHEd25519PrivateKeyParser.load(from: URL(fileURLWithPath: path))
            return SinglePrivateKeyDelegate(username: scenario.username, privateKey: privateKey)
        }
    }
}

private final class RootSSHErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

private final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

private final class SinglePrivateKeyDelegate: NIOSSHClientUserAuthenticationDelegate {
    private var offer: NIOSSHUserAuthenticationOffer?

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.offer = NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: privateKey))
        )
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if let offer, availableMethods.contains(.publicKey) {
            self.offer = nil
            nextChallengePromise.succeed(offer)
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

private final class SSHExecCaptureHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let scenario: SSHSmokeScenario
    private let resultPromise: EventLoopPromise<SSHSmokeResult>
    private var standardOutput = ByteBuffer()
    private var standardError = ByteBuffer()
    private var exitStatus: Int?
    private var execAccepted = false
    private var completed = false

    init(scenario: SSHSmokeScenario, resultPromise: EventLoopPromise<SSHSmokeResult>) {
        self.scenario = scenario
        self.resultPromise = resultPromise
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let setOption = context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        setOption.whenFailure { error in
            context.fireErrorCaught(error)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        let execRequest = SSHChannelRequestEvent.ExecRequest(command: scenario.command, wantReply: true)
        context.triggerUserOutboundEvent(execRequest).whenFailure { _ in
            self.resultPromise.fail(SSHSmokeClientError.execRequestRejected)
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            execAccepted = true
            context.close(mode: .output, promise: nil)
        case is ChannelFailureEvent:
            resultPromise.fail(SSHSmokeClientError.execRequestRejected)
            context.close(promise: nil)
        case let exit as SSHChannelRequestEvent.ExitStatus:
            exitStatus = exit.exitStatus
            succeedIfPossible()
        case is ChannelEvent:
            succeedIfPossible()
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)
        guard case let .byteBuffer(buffer) = data.data else {
            return
        }

        switch data.type {
        case .channel:
            var copy = buffer
            standardOutput.writeBuffer(&copy)
        case .stdErr:
            var copy = buffer
            standardError.writeBuffer(&copy)
        default:
            break
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        succeedIfPossible()
    }

    private func succeedIfPossible() {
        guard !completed, execAccepted, let exitStatus else { return }
        completed = true
        let result = SSHSmokeResult(
            authentication: scenario.authentication.label,
            exitStatus: exitStatus,
            standardOutput: standardOutput.getString(at: 0, length: standardOutput.readableBytes) ?? "",
            standardError: standardError.getString(at: 0, length: standardError.readableBytes) ?? ""
        )
        resultPromise.succeed(result)
    }
}

enum OpenSSHEd25519PrivateKeyParser {
    static func load(from url: URL) throws -> NIOSSHPrivateKey {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(pem: content)
    }

    static func parse(pem: String) throws -> NIOSSHPrivateKey {
        let normalized = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard let data = Data(base64Encoded: normalized) else {
            throw SSHSmokeClientError.invalidOpenSSHKey("base64-decoding failed")
        }

        var reader = SSHBinaryReader(data: data)
        let magic = try reader.readBytes(count: "openssh-key-v1\u{0}".utf8.count)
        guard String(decoding: magic, as: UTF8.self) == "openssh-key-v1\u{0}" else {
            throw SSHSmokeClientError.invalidOpenSSHKey("unexpected magic header")
        }

        let cipherName = try reader.readString()
        let kdfName = try reader.readString()
        _ = try reader.readStringData()
        let keyCount = try reader.readUInt32()

        guard cipherName == "none", kdfName == "none" else {
            throw SSHSmokeClientError.unsupportedPrivateKey("encrypted-key")
        }
        guard keyCount == 1 else {
            throw SSHSmokeClientError.invalidOpenSSHKey("expected one key, found \(keyCount)")
        }

        _ = try reader.readStringData()
        let privateBlockData = try reader.readStringData()
        var privateReader = SSHBinaryReader(data: privateBlockData)

        let checkOne = try privateReader.readUInt32()
        let checkTwo = try privateReader.readUInt32()
        guard checkOne == checkTwo else {
            throw SSHSmokeClientError.invalidOpenSSHKey("private block checksum mismatch")
        }

        let keyType = try privateReader.readString()
        guard keyType == "ssh-ed25519" else {
            throw SSHSmokeClientError.invalidKeyType(keyType)
        }

        let publicKeyData = try privateReader.readStringData()
        let privateKeyData = try privateReader.readStringData()
        _ = try privateReader.readString()

        guard privateKeyData.count >= 32 else {
            throw SSHSmokeClientError.invalidOpenSSHKey("ed25519 private key was too short")
        }

        let rawPrivateKey = privateKeyData.prefix(32)
        let cryptoKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
        let nioKey = NIOSSHPrivateKey(ed25519Key: cryptoKey)

        let derivedPublic = Data(cryptoKey.publicKey.rawRepresentation)
        guard publicKeyData == derivedPublic else {
            throw SSHSmokeClientError.invalidOpenSSHKey("public key validation failed")
        }

        return nioKey
    }
}

private func shutdown(_ group: MultiThreadedEventLoopGroup) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        group.shutdownGracefully { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: ())
            }
        }
    }
}

private struct SSHBinaryReader {
    private let data: Data
    private var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readString() throws -> String {
        let bytes = try readStringData()
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw SSHSmokeClientError.invalidOpenSSHKey("invalid UTF-8 string")
        }
        return value
    }

    mutating func readStringData() throws -> Data {
        let count = try Int(exactly: readUInt32())
            ?? {
                throw SSHSmokeClientError.invalidOpenSSHKey("invalid string length")
            }()
        return try readData(count: count)
    }

    mutating func readData(count: Int) throws -> Data {
        Data(try readBytes(count: count))
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0 else {
            throw SSHSmokeClientError.invalidOpenSSHKey("negative byte count")
        }
        let endIndex = data.index(index, offsetBy: count, limitedBy: data.endIndex)
        guard let endIndex else {
            throw SSHSmokeClientError.invalidOpenSSHKey("unexpected end of data")
        }
        let slice = Array(data[index..<endIndex])
        index = endIndex
        return slice
    }
}
