import Foundation

/// Configuration for terminal appearance and behavior.
public struct TerminalConfiguration: Sendable, Codable {
    public var fontFamily: String = "SF Mono"
    public var fontSize: Double = 14
    public var colorScheme: TerminalColorScheme = .defaultDark
    public var scrollbackLines: Int = 10_000
    public var cursorStyle: CursorStyle = .block
    public var cursorBlink: Bool = true
    public var bellSound: Bool = true

    public init(
        fontFamily: String = "SF Mono",
        fontSize: Double = 14,
        colorScheme: TerminalColorScheme = .defaultDark,
        scrollbackLines: Int = 10_000,
        cursorStyle: CursorStyle = .block,
        cursorBlink: Bool = true,
        bellSound: Bool = true
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.colorScheme = colorScheme
        self.scrollbackLines = scrollbackLines
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.bellSound = bellSound
    }

    public enum CursorStyle: String, Sendable, Codable, CaseIterable {
        case block
        case underline
        case bar
    }
}

public enum TerminalColorScheme: String, Sendable, Codable, CaseIterable {
    case defaultDark = "Default Dark"
    case defaultLight = "Default Light"
    case solarizedDark = "Solarized Dark"
    case solarizedLight = "Solarized Light"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"
    case tokyoNight = "Tokyo Night"

    public var backgroundColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .defaultDark: return (0, 0, 0)
        case .defaultLight: return (255, 255, 255)
        case .solarizedDark: return (0, 43, 54)
        case .solarizedLight: return (253, 246, 227)
        case .dracula: return (40, 42, 54)
        case .monokai: return (39, 40, 34)
        case .nord: return (46, 52, 64)
        case .tokyoNight: return (26, 27, 38)
        }
    }

    public var foregroundColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .defaultDark: return (204, 204, 204)
        case .defaultLight: return (0, 0, 0)
        case .solarizedDark: return (131, 148, 150)
        case .solarizedLight: return (101, 123, 131)
        case .dracula: return (248, 248, 242)
        case .monokai: return (248, 248, 242)
        case .nord: return (216, 222, 233)
        case .tokyoNight: return (169, 177, 214)
        }
    }
}
