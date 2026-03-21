import Foundation

public protocol TerminalIO: Sendable {
    func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) async
    func write(_ data: Data) async
}
