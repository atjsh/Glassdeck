
import Foundation
import NIO
import NIOSSH

class StartShellHandler: ChannelInboundHandler {
    private enum StartState {
        case requestPTY
        case requestShell
        case started
    }

    typealias InboundIn = SSHChannelData

    let handler: () -> Void
    private let pty: SSHPseudoTerminal?

    // To avoid multiple starts
    private var isStarted = false
    private var startState: StartState

    init(pty: SSHPseudoTerminal?, handler: @escaping () -> Void) {
        self.pty = pty
        self.handler = handler
        self.startState = pty == nil ? .requestShell : .requestPTY
    }

    deinit {}

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenComplete { result in
            switch result {
            case .success:
                self.sendNextRequest(context: context)
            case .failure:
                context.channel.close(promise: nil)
            }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            switch startState {
            case .requestPTY:
                startState = .requestShell
                sendNextRequest(context: context)
            case .requestShell:
                startState = .started
                triggerStart()
            case .started:
                break
            }
        case is ChannelFailureEvent:
            context.channel.close(promise: nil)
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    private func sendNextRequest(context: ChannelHandlerContext) {
        let request: Any
        switch startState {
        case .requestPTY:
            guard let pty else {
                context.channel.close(promise: nil)
                return
            }
            request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: pty.term,
                terminalCharacterWidth: pty.size.terminalCharacterWidth,
                terminalRowHeight: pty.size.terminalRowHeight,
                terminalPixelWidth: pty.size.terminalPixelWidth,
                terminalPixelHeight: pty.size.terminalPixelHeight,
                terminalModes: pty.terminalModes
            )
        case .requestShell:
            request = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        case .started:
            return
        }

        let promise = context.channel.eventLoop.makePromise(of: Void.self)
        context.triggerUserOutboundEvent(request, promise: promise)
        promise.futureResult.whenFailure { _ in
            context.channel.close(promise: nil)
        }
    }

    private func triggerStart() {
        guard !isStarted else { return }
        isStarted = true
        handler()
    }
}

class ReadShellHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    let onData: (Data) -> Void

    init(onData: @escaping (Data) -> Void) {
        self.onData = onData
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = sshData.data, let bytes = buffer.readData(length: buffer.readableBytes) else {
            return
        }
        switch sshData.type {
        case .channel:
            onData(bytes)
        case .stdErr:
            onData(bytes)
        default:
            break
        }
        context.fireChannelRead(data)
    }
}
