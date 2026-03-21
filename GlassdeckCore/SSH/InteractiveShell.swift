import Foundation

public struct ShellLaunchConfiguration: Sendable, Equatable {
    public var term: String = "xterm-256color"
    public var size: TerminalSize = .init(columns: 80, rows: 24)
    public var pixelSize: TerminalPixelSize? = nil

    public static let `default` = ShellLaunchConfiguration()

    public init(
        term: String = "xterm-256color",
        size: TerminalSize = .init(columns: 80, rows: 24),
        pixelSize: TerminalPixelSize? = nil
    ) {
        self.term = term
        self.size = size
        self.pixelSize = pixelSize
    }
}

public protocol InteractiveShell: Sendable {
    var output: AsyncThrowingStream<Data, Error> { get }

    func write(_ data: Data) async throws
    func resize(
        to size: TerminalSize,
        pixelSize: TerminalPixelSize?
    ) async throws
    func close() async
}
