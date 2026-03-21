import Foundation

/// Configuration for terminal appearance and behavior.
public struct TerminalConfiguration: Sendable, Codable, Equatable {
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

    public enum CursorStyle: String, Sendable, Codable, CaseIterable, Equatable {
        case block
        case underline
        case bar
    }
}

public struct TerminalTheme: Sendable, Equatable {
    public var background: GhosttyVTColor
    public var foreground: GhosttyVTColor
    public var cursor: GhosttyVTColor
    public var palette: [GhosttyVTColor]

    public init(
        background: GhosttyVTColor,
        foreground: GhosttyVTColor,
        cursor: GhosttyVTColor,
        palette: [GhosttyVTColor]
    ) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.palette = palette
    }
}

public enum TerminalColorScheme: String, Sendable, Codable, CaseIterable, Equatable {
    case defaultDark = "Default Dark"
    case defaultLight = "Default Light"
    case solarizedDark = "Solarized Dark"
    case solarizedLight = "Solarized Light"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"
    case tokyoNight = "Tokyo Night"

    public var theme: TerminalTheme {
        switch self {
        case .defaultDark:
            return Self.theme(
                background: (0, 0, 0),
                foreground: (229, 229, 229),
                cursor: (229, 229, 229),
                ansi: [
                    (0, 0, 0),
                    (205, 0, 0),
                    (0, 205, 0),
                    (205, 205, 0),
                    (0, 0, 238),
                    (205, 0, 205),
                    (0, 205, 205),
                    (229, 229, 229),
                    (127, 127, 127),
                    (255, 0, 0),
                    (0, 255, 0),
                    (255, 255, 0),
                    (92, 92, 255),
                    (255, 0, 255),
                    (0, 255, 255),
                    (255, 255, 255),
                ]
            )
        case .defaultLight:
            return Self.theme(
                background: (255, 255, 255),
                foreground: (0, 0, 0),
                cursor: (0, 0, 0),
                ansi: [
                    (0, 0, 0),
                    (205, 49, 49),
                    (0, 166, 0),
                    (148, 123, 0),
                    (4, 81, 165),
                    (188, 63, 188),
                    (5, 152, 188),
                    (187, 187, 187),
                    (102, 102, 102),
                    (241, 76, 76),
                    (35, 209, 139),
                    (245, 245, 67),
                    (59, 142, 234),
                    (214, 112, 214),
                    (41, 184, 219),
                    (229, 229, 229),
                ]
            )
        case .solarizedDark:
            return Self.theme(
                background: (0, 43, 54),
                foreground: (131, 148, 150),
                cursor: (147, 161, 161),
                ansi: [
                    (7, 54, 66),
                    (220, 50, 47),
                    (133, 153, 0),
                    (181, 137, 0),
                    (38, 139, 210),
                    (211, 54, 130),
                    (42, 161, 152),
                    (238, 232, 213),
                    (0, 43, 54),
                    (203, 75, 22),
                    (88, 110, 117),
                    (101, 123, 131),
                    (131, 148, 150),
                    (108, 113, 196),
                    (147, 161, 161),
                    (253, 246, 227),
                ]
            )
        case .solarizedLight:
            return Self.theme(
                background: (253, 246, 227),
                foreground: (101, 123, 131),
                cursor: (88, 110, 117),
                ansi: [
                    (7, 54, 66),
                    (220, 50, 47),
                    (133, 153, 0),
                    (181, 137, 0),
                    (38, 139, 210),
                    (211, 54, 130),
                    (42, 161, 152),
                    (238, 232, 213),
                    (0, 43, 54),
                    (203, 75, 22),
                    (88, 110, 117),
                    (101, 123, 131),
                    (131, 148, 150),
                    (108, 113, 196),
                    (147, 161, 161),
                    (253, 246, 227),
                ]
            )
        case .dracula:
            return Self.theme(
                background: (40, 42, 54),
                foreground: (248, 248, 242),
                cursor: (248, 248, 242),
                ansi: [
                    (33, 34, 44),
                    (255, 85, 85),
                    (80, 250, 123),
                    (241, 250, 140),
                    (189, 147, 249),
                    (255, 121, 198),
                    (139, 233, 253),
                    (248, 248, 242),
                    (98, 114, 164),
                    (255, 110, 110),
                    (105, 255, 148),
                    (246, 255, 165),
                    (214, 172, 255),
                    (255, 146, 223),
                    (164, 255, 255),
                    (255, 255, 255),
                ]
            )
        case .monokai:
            return Self.theme(
                background: (39, 40, 34),
                foreground: (248, 248, 242),
                cursor: (248, 248, 242),
                ansi: [
                    (39, 40, 34),
                    (249, 38, 114),
                    (166, 226, 46),
                    (253, 151, 31),
                    (102, 217, 239),
                    (174, 129, 255),
                    (161, 239, 228),
                    (248, 248, 242),
                    (117, 113, 94),
                    (255, 89, 149),
                    (191, 251, 71),
                    (255, 176, 56),
                    (127, 242, 255),
                    (199, 154, 255),
                    (186, 255, 253),
                    (255, 255, 255),
                ]
            )
        case .nord:
            return Self.theme(
                background: (46, 52, 64),
                foreground: (216, 222, 233),
                cursor: (236, 239, 244),
                ansi: [
                    (59, 66, 82),
                    (191, 97, 106),
                    (163, 190, 140),
                    (235, 203, 139),
                    (129, 161, 193),
                    (180, 142, 173),
                    (136, 192, 208),
                    (229, 233, 240),
                    (76, 86, 106),
                    (191, 97, 106),
                    (163, 190, 140),
                    (235, 203, 139),
                    (129, 161, 193),
                    (180, 142, 173),
                    (143, 188, 187),
                    (236, 239, 244),
                ]
            )
        case .tokyoNight:
            return Self.theme(
                background: (26, 27, 38),
                foreground: (169, 177, 214),
                cursor: (192, 202, 245),
                ansi: [
                    (26, 27, 38),
                    (247, 118, 142),
                    (158, 206, 106),
                    (224, 175, 104),
                    (122, 162, 247),
                    (187, 154, 247),
                    (125, 207, 255),
                    (192, 202, 245),
                    (65, 72, 104),
                    (255, 142, 166),
                    (182, 230, 130),
                    (248, 199, 128),
                    (146, 186, 255),
                    (211, 178, 255),
                    (149, 231, 255),
                    (214, 222, 255),
                ]
            )
        }
    }

    public var backgroundColor: (r: UInt8, g: UInt8, b: UInt8) {
        let color = theme.background
        return (color.r, color.g, color.b)
    }

    public var foregroundColor: (r: UInt8, g: UInt8, b: UInt8) {
        let color = theme.foreground
        return (color.r, color.g, color.b)
    }

    public var cursorColor: (r: UInt8, g: UInt8, b: UInt8) {
        let color = theme.cursor
        return (color.r, color.g, color.b)
    }

    private static func theme(
        background: (UInt8, UInt8, UInt8),
        foreground: (UInt8, UInt8, UInt8),
        cursor: (UInt8, UInt8, UInt8),
        ansi: [(UInt8, UInt8, UInt8)]
    ) -> TerminalTheme {
        TerminalTheme(
            background: color(background),
            foreground: color(foreground),
            cursor: color(cursor),
            palette: ansi.map { color($0) } + extendedPalette
        )
    }

    private static let extendedPalette: [GhosttyVTColor] = {
        var palette: [GhosttyVTColor] = []
        let cubeLevels: [UInt8] = [0, 95, 135, 175, 215, 255]
        for red in cubeLevels {
            for green in cubeLevels {
                for blue in cubeLevels {
                    palette.append(GhosttyVTColor(r: red, g: green, b: blue))
                }
            }
        }

        for step in 0..<24 {
            let value = UInt8(8 + (step * 10))
            palette.append(GhosttyVTColor(r: value, g: value, b: value))
        }

        return palette
    }()

    private static func color(_ rgb: (UInt8, UInt8, UInt8)) -> GhosttyVTColor {
        GhosttyVTColor(r: rgb.0, g: rgb.1, b: rgb.2)
    }
}
