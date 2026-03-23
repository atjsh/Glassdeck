import Foundation

public struct TerminalSize: Sendable, Equatable, Codable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

public struct TerminalPixelSize: Sendable, Equatable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct GhosttyVTColor: Sendable, Equatable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hexString: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }
}

public struct GhosttyVTInteractionCapabilities: Sendable, Equatable {
    public var supportsMousePlacement: Bool
    public var supportsScrollReporting: Bool

    public init(
        supportsMousePlacement: Bool,
        supportsScrollReporting: Bool
    ) {
        self.supportsMousePlacement = supportsMousePlacement
        self.supportsScrollReporting = supportsScrollReporting
    }
}
