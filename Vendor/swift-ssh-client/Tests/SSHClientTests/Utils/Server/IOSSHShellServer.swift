import Crypto
import Dispatch
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SSHClient

final class IOSSHShellServer: SSHServer {
    var receivedBuffer = Data()
    var ptyRequests: [SSHChannelRequestEvent.PseudoTerminalRequest] = []
    var windowChangeRequests: [SSHChannelRequestEvent.WindowChangeRequest] = []

    let username: String
    let password: String
    let host: String
    let port: UInt16

    var timeBeforeAuthentication: TimeInterval = 0.0

    private(set) var authenticationCount = 0

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    private var channel: Channel?
    private var child: Channel?

    var hasActiveChild: Bool {
        child?.isActive ?? false
    }

    init(expectedUsername: String,
         expectedPassword: String,
         host: String,
         port: UInt16) {
        username = expectedUsername
        password = expectedPassword
        self.host = host
        self.port = port
    }

    func end() {
        _ = try? channel?.close().wait()
        group.shutdownGracefully { _ in }
        channel = nil
        child = nil
    }

    func waitClosing() {
        try? channel?.closeFuture.wait()
    }

    func run() throws {
        let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                self.child = channel
                return channel.pipeline.addHandlers(
                    [
                        NIOSSHHandler(
                            role: .server(.init(
                                hostKeys: [hostKey],
                                userAuthDelegate: HardcodedPasswordDelegate(
                                    expectedUsername: self.username,
                                    expectedPassword: self.password,
                                    hasReceivedRequest: {
                                        self.authenticationCount += 1
                                    },
                                    timeBeforeAuthentication: { self.timeBeforeAuthentication }
                                )
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: self.sshChildChannelInitializer(_:channelType:)
                        ),
                    ]
                )
            }
            .serverChannelOption(
                ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR),
                value: 1
            )
            .serverChannelOption(
                ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY),
                value: 1
            )

        channel = try bootstrap.bind(host: "0.0.0.0", port: Int(port)).wait()
    }

    private func sshChildChannelInitializer(_ channel: Channel,
                                            channelType: SSHChannelType) -> EventLoopFuture<Void> {
        switch channelType {
        case .session:
            child = channel
            return channel.pipeline.addHandler(
                ExampleShellHandler(server: self)
            )
        case .directTCPIP, .forwardedTCPIP:
            fatalError("NOT AVAILABLE")
        }
    }
}

final class ExampleShellHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let server: IOSSHShellServer

    init(server: IOSSHShellServer) {
        self.server = server
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            context.fireErrorCaught(error)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let request as SSHChannelRequestEvent.PseudoTerminalRequest:
            server.ptyRequests.append(request)
            if request.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
        case let request as SSHChannelRequestEvent.ShellRequest:
            if request.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
        case let request as SSHChannelRequestEvent.WindowChangeRequest:
            server.windowChangeRequests.append(request)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)

        guard case .byteBuffer(var buffer) = data.data,
              let bytes = buffer.readData(length: buffer.readableBytes) else {
            return
        }

        guard case .channel = data.type else {
            return
        }

        server.receivedBuffer.append(bytes)
        let response = context.channel.allocator.buffer(data: bytes)
        context.writeAndFlush(
            wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(response))),
            promise: nil
        )
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(data))), promise: promise)
    }
}
