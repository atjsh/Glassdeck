import Foundation
import NIOSSH

public typealias SSHTerminalModes = NIOSSH.SSHTerminalModes

public struct SSHWindowSize: Hashable, Sendable {
    public var terminalCharacterWidth: Int
    public var terminalRowHeight: Int
    public var terminalPixelWidth: Int
    public var terminalPixelHeight: Int

    public init(terminalCharacterWidth: Int,
                terminalRowHeight: Int,
                terminalPixelWidth: Int = 0,
                terminalPixelHeight: Int = 0) {
        self.terminalCharacterWidth = terminalCharacterWidth
        self.terminalRowHeight = terminalRowHeight
        self.terminalPixelWidth = terminalPixelWidth
        self.terminalPixelHeight = terminalPixelHeight
    }
}

public struct SSHPseudoTerminal: Hashable, Sendable {
    public var term: String
    public var size: SSHWindowSize
    public var terminalModes: SSHTerminalModes

    public init(term: String,
                size: SSHWindowSize,
                terminalModes: SSHTerminalModes = .init([:])) {
        self.term = term
        self.size = size
        self.terminalModes = terminalModes
    }
}
