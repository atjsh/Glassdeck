import SwiftUI

/// Configuration for terminal appearance and behavior.
struct TerminalConfiguration: Sendable, Codable {
    var fontFamily: String = "SF Mono"
    var fontSize: CGFloat = 14
    var colorScheme: TerminalColorScheme = .defaultDark
    var scrollbackLines: Int = 10_000
    var cursorStyle: CursorStyle = .block
    var cursorBlink: Bool = true
    var bellSound: Bool = true

    enum CursorStyle: String, Sendable, Codable, CaseIterable {
        case block
        case underline
        case bar
    }
}

enum TerminalColorScheme: String, Sendable, Codable, CaseIterable {
    case defaultDark = "Default Dark"
    case defaultLight = "Default Light"
    case solarizedDark = "Solarized Dark"
    case solarizedLight = "Solarized Light"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"
    case tokyoNight = "Tokyo Night"

    var backgroundColor: (r: UInt8, g: UInt8, b: UInt8) {
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

    var foregroundColor: (r: UInt8, g: UInt8, b: UInt8) {
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
