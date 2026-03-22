import Foundation

public enum GhosttyVTDirtyState: Sendable, Equatable {
    case clean
    case partial
    case full
}

public struct GhosttyVTColor: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum GhosttyVTStyleColor: Sendable, Equatable {
    case none
    case palette(UInt8)
    case rgb(GhosttyVTColor)
}

public struct GhosttyVTTextStyle: Sendable, Equatable {
    public var foreground: GhosttyVTStyleColor
    public var background: GhosttyVTStyleColor
    public var underlineColor: GhosttyVTStyleColor
    public var bold: Bool
    public var italic: Bool
    public var faint: Bool
    public var blink: Bool
    public var inverse: Bool
    public var invisible: Bool
    public var strikethrough: Bool
    public var overline: Bool
    public var underline: Int

    public init(
        foreground: GhosttyVTStyleColor = .none,
        background: GhosttyVTStyleColor = .none,
        underlineColor: GhosttyVTStyleColor = .none,
        bold: Bool = false,
        italic: Bool = false,
        faint: Bool = false,
        blink: Bool = false,
        inverse: Bool = false,
        invisible: Bool = false,
        strikethrough: Bool = false,
        overline: Bool = false,
        underline: Int = 0
    ) {
        self.foreground = foreground
        self.background = background
        self.underlineColor = underlineColor
        self.bold = bold
        self.italic = italic
        self.faint = faint
        self.blink = blink
        self.inverse = inverse
        self.invisible = invisible
        self.strikethrough = strikethrough
        self.overline = overline
        self.underline = underline
    }
}

public enum GhosttyVTCellWidth: Sendable, Equatable {
    case narrow
    case wide
    case spacerTail
    case spacerHead
}

public struct GhosttyVTCellProjection: Sendable, Equatable {
    public var column: Int
    public var text: String
    public var style: GhosttyVTTextStyle
    public var width: GhosttyVTCellWidth

    public init(
        column: Int,
        text: String,
        style: GhosttyVTTextStyle,
        width: GhosttyVTCellWidth
    ) {
        self.column = column
        self.text = text
        self.style = style
        self.width = width
    }
}

public struct GhosttyVTRowProjection: Sendable, Equatable {
    public var index: Int
    public var dirty: Bool
    public var wrapped: Bool
    public var wrapContinuation: Bool
    public var cells: [GhosttyVTCellProjection]

    public init(
        index: Int,
        dirty: Bool,
        wrapped: Bool,
        wrapContinuation: Bool,
        cells: [GhosttyVTCellProjection]
    ) {
        self.index = index
        self.dirty = dirty
        self.wrapped = wrapped
        self.wrapContinuation = wrapContinuation
        self.cells = cells
    }
}

public enum GhosttyVTCursorVisualStyle: Sendable, Equatable {
    case bar
    case block
    case underline
    case hollowBlock
}

public struct GhosttyVTCursorProjection: Sendable, Equatable {
    public var visualStyle: GhosttyVTCursorVisualStyle
    public var visible: Bool
    public var blinking: Bool
    public var passwordInput: Bool
    public var x: Int?
    public var y: Int?
    public var wideTail: Bool

    public init(
        visualStyle: GhosttyVTCursorVisualStyle,
        visible: Bool,
        blinking: Bool,
        passwordInput: Bool,
        x: Int?,
        y: Int?,
        wideTail: Bool
    ) {
        self.visualStyle = visualStyle
        self.visible = visible
        self.blinking = blinking
        self.passwordInput = passwordInput
        self.x = x
        self.y = y
        self.wideTail = wideTail
    }
}

public struct GhosttyVTScrollbarProjection: Sendable, Equatable {
    public var total: UInt64
    public var offset: UInt64
    public var length: UInt64

    public init(total: UInt64, offset: UInt64, length: UInt64) {
        self.total = total
        self.offset = offset
        self.length = length
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

public struct GhosttyVTRenderProjection: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var dirtyState: GhosttyVTDirtyState
    public var dirtyRows: [Int]
    public var backgroundColor: GhosttyVTColor
    public var foregroundColor: GhosttyVTColor
    public var cursorColor: GhosttyVTColor?
    public var palette: [GhosttyVTColor]
    public var cursor: GhosttyVTCursorProjection
    public var rowsProjection: [GhosttyVTRowProjection]
    public var scrollbar: GhosttyVTScrollbarProjection?

    public init(
        columns: Int,
        rows: Int,
        dirtyState: GhosttyVTDirtyState,
        dirtyRows: [Int],
        backgroundColor: GhosttyVTColor,
        foregroundColor: GhosttyVTColor,
        cursorColor: GhosttyVTColor?,
        palette: [GhosttyVTColor],
        cursor: GhosttyVTCursorProjection,
        rowsProjection: [GhosttyVTRowProjection],
        scrollbar: GhosttyVTScrollbarProjection?
    ) {
        self.columns = columns
        self.rows = rows
        self.dirtyState = dirtyState
        self.dirtyRows = dirtyRows
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.cursorColor = cursorColor
        self.palette = palette
        self.cursor = cursor
        self.rowsProjection = rowsProjection
        self.scrollbar = scrollbar
    }
}

public struct GhosttyVTModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let shift = GhosttyVTModifiers(rawValue: 1 << 0)
    public static let control = GhosttyVTModifiers(rawValue: 1 << 1)
    public static let alt = GhosttyVTModifiers(rawValue: 1 << 2)
    public static let `super` = GhosttyVTModifiers(rawValue: 1 << 3)
    public static let capsLock = GhosttyVTModifiers(rawValue: 1 << 4)
    public static let numLock = GhosttyVTModifiers(rawValue: 1 << 5)
}

public enum GhosttyVTKeyAction: Sendable, Equatable {
    case press
    case release
    case `repeat`
}

public enum GhosttyVTKeyCode: Sendable, Equatable {
    case unidentified
    case backquote
    case backslash
    case bracketLeft
    case bracketRight
    case comma
    case digit0
    case digit1
    case digit2
    case digit3
    case digit4
    case digit5
    case digit6
    case digit7
    case digit8
    case digit9
    case equal
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z
    case minus
    case period
    case quote
    case semicolon
    case slash
    case altLeft
    case altRight
    case backspace
    case capsLock
    case controlLeft
    case controlRight
    case enter
    case metaLeft
    case metaRight
    case shiftLeft
    case shiftRight
    case space
    case tab
    case delete
    case end
    case home
    case insert
    case pageDown
    case pageUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case arrowUp
    case escape
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
}

public struct GhosttyVTKeyEventDescriptor: Sendable, Equatable {
    public var action: GhosttyVTKeyAction
    public var keyCode: GhosttyVTKeyCode?
    public var modifiers: GhosttyVTModifiers
    public var text: String
    public var unshiftedText: String?
    public var composing: Bool

    public init(
        action: GhosttyVTKeyAction = .press,
        keyCode: GhosttyVTKeyCode? = nil,
        modifiers: GhosttyVTModifiers = [],
        text: String = "",
        unshiftedText: String? = nil,
        composing: Bool = false
    ) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.text = text
        self.unshiftedText = unshiftedText
        self.composing = composing
    }
}

public enum GhosttyVTMouseAction: Sendable, Equatable {
    case press
    case release
    case motion
}

public enum GhosttyVTMouseButton: Sendable, Equatable {
    case left
    case right
    case middle
    case button4
    case button5
}

public struct GhosttyVTPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GhosttyVTMouseSizeContext: Sendable, Equatable {
    public var screenWidth: Int
    public var screenHeight: Int
    public var cellWidth: Int
    public var cellHeight: Int
    public var paddingTop: Int
    public var paddingBottom: Int
    public var paddingRight: Int
    public var paddingLeft: Int

    public init(
        screenWidth: Int,
        screenHeight: Int,
        cellWidth: Int,
        cellHeight: Int,
        paddingTop: Int = 0,
        paddingBottom: Int = 0,
        paddingRight: Int = 0,
        paddingLeft: Int = 0
    ) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.paddingTop = paddingTop
        self.paddingBottom = paddingBottom
        self.paddingRight = paddingRight
        self.paddingLeft = paddingLeft
    }
}

public struct GhosttyVTMouseEventDescriptor: Sendable, Equatable {
    public var action: GhosttyVTMouseAction
    public var button: GhosttyVTMouseButton?
    public var modifiers: GhosttyVTModifiers
    public var position: GhosttyVTPoint
    public var sizeContext: GhosttyVTMouseSizeContext

    public init(
        action: GhosttyVTMouseAction,
        button: GhosttyVTMouseButton?,
        modifiers: GhosttyVTModifiers = [],
        position: GhosttyVTPoint,
        sizeContext: GhosttyVTMouseSizeContext
    ) {
        self.action = action
        self.button = button
        self.modifiers = modifiers
        self.position = position
        self.sizeContext = sizeContext
    }
}
