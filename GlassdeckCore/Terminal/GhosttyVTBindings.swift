import Foundation

#if canImport(CGhosttyVT)
import CGhosttyVT

public enum GhosttyVTBindings {
    public static let isLinked = true
}

public struct GhosttyVTTerminalOptions: Sendable {
    public var columns: UInt16
    public var rows: UInt16
    public var scrollbackLines: Int

    public init(
        columns: UInt16 = 80,
        rows: UInt16 = 24,
        scrollbackLines: Int = 10_000
    ) {
        self.columns = columns
        self.rows = rows
        self.scrollbackLines = scrollbackLines
    }
}

public enum GhosttyVTError: Error, LocalizedError {
    case unavailable
    case operationFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "CGhosttyVT is unavailable for the current build."
        case .operationFailed(let code):
            "libghostty-vt operation failed with code \(code)."
        }
    }
}

public final class GhosttyVTTerminalEngine {
    public let options: GhosttyVTTerminalOptions

    private var terminal: GhosttyTerminal?
    private var renderState: GhosttyRenderState?
    private var keyEncoder: GhosttyKeyEncoder?
    private var mouseEncoder: GhosttyMouseEncoder?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
    private var anyMouseButtonPressed = false

    public init(options: GhosttyVTTerminalOptions = GhosttyVTTerminalOptions()) throws {
        self.options = options

        var terminal: GhosttyTerminal?
        let terminalOptions = GhosttyTerminalOptions(
            cols: options.columns,
            rows: options.rows,
            max_scrollback: numericCast(max(0, options.scrollbackLines))
        )
        try Self.check(
            ghostty_terminal_new(nil, &terminal, terminalOptions)
        )

        var renderState: GhosttyRenderState?
        do {
            try Self.check(
                ghostty_render_state_new(nil, &renderState)
            )
        } catch {
            if let terminal {
                ghostty_terminal_free(terminal)
            }
            throw error
        }

        var keyEncoder: GhosttyKeyEncoder?
        do {
            try Self.check(
                ghostty_key_encoder_new(nil, &keyEncoder)
            )
        } catch {
            if let renderState {
                ghostty_render_state_free(renderState)
            }
            if let terminal {
                ghostty_terminal_free(terminal)
            }
            throw error
        }

        var mouseEncoder: GhosttyMouseEncoder?
        do {
            try Self.check(
                ghostty_mouse_encoder_new(nil, &mouseEncoder)
            )
        } catch {
            if let keyEncoder {
                ghostty_key_encoder_free(keyEncoder)
            }
            if let renderState {
                ghostty_render_state_free(renderState)
            }
            if let terminal {
                ghostty_terminal_free(terminal)
            }
            throw error
        }

        var rowIterator: GhosttyRenderStateRowIterator?
        do {
            try Self.check(
                ghostty_render_state_row_iterator_new(nil, &rowIterator)
            )
        } catch {
            if let mouseEncoder {
                ghostty_mouse_encoder_free(mouseEncoder)
            }
            if let keyEncoder {
                ghostty_key_encoder_free(keyEncoder)
            }
            if let renderState {
                ghostty_render_state_free(renderState)
            }
            if let terminal {
                ghostty_terminal_free(terminal)
            }
            throw error
        }

        var rowCells: GhosttyRenderStateRowCells?
        do {
            try Self.check(
                ghostty_render_state_row_cells_new(nil, &rowCells)
            )
        } catch {
            if let rowIterator {
                ghostty_render_state_row_iterator_free(rowIterator)
            }
            if let mouseEncoder {
                ghostty_mouse_encoder_free(mouseEncoder)
            }
            if let keyEncoder {
                ghostty_key_encoder_free(keyEncoder)
            }
            if let renderState {
                ghostty_render_state_free(renderState)
            }
            if let terminal {
                ghostty_terminal_free(terminal)
            }
            throw error
        }

        self.terminal = terminal
        self.renderState = renderState
        self.keyEncoder = keyEncoder
        self.mouseEncoder = mouseEncoder
        self.rowIterator = rowIterator
        self.rowCells = rowCells
    }

    deinit {
        if let rowCells {
            ghostty_render_state_row_cells_free(rowCells)
        }
        if let rowIterator {
            ghostty_render_state_row_iterator_free(rowIterator)
        }
        if let mouseEncoder {
            ghostty_mouse_encoder_free(mouseEncoder)
        }
        if let keyEncoder {
            ghostty_key_encoder_free(keyEncoder)
        }
        if let renderState {
            ghostty_render_state_free(renderState)
        }
        if let terminal {
            ghostty_terminal_free(terminal)
        }
    }

    public func write(_ data: Data) {
        guard let terminal, !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            ghostty_terminal_vt_write(terminal, baseAddress, rawBuffer.count)
        }
    }

    public func resize(columns: UInt16, rows: UInt16) throws {
        guard let terminal else {
            throw GhosttyVTError.unavailable
        }
        try Self.check(
            ghostty_terminal_resize(terminal, columns, rows)
        )
    }

    public func scrollViewport(delta: Int) {
        guard let terminal else { return }
        var viewport = GhosttyTerminalScrollViewport(
            tag: GHOSTTY_SCROLL_VIEWPORT_DELTA,
            value: GhosttyTerminalScrollViewportValue()
        )
        viewport.value.delta = numericCast(delta)
        ghostty_terminal_scroll_viewport(terminal, viewport)
    }

    public func currentSize() throws -> TerminalSize {
        guard let terminal else {
            throw GhosttyVTError.unavailable
        }
        let columns = try Self.terminalValue(terminal, data: GHOSTTY_TERMINAL_DATA_COLS, default: UInt16(options.columns))
        let rows = try Self.terminalValue(terminal, data: GHOSTTY_TERMINAL_DATA_ROWS, default: UInt16(options.rows))
        return TerminalSize(columns: Int(columns), rows: Int(rows))
    }

    public func encodeKey(_ event: GhosttyVTKeyEventDescriptor) throws -> Data? {
        if event.keyCode == nil, event.modifiers.isEmpty {
            switch event.action {
            case .press, .repeat:
                return event.text.isEmpty ? nil : Data(event.text.utf8)
            case .release:
                return nil
            }
        }

        guard
            let terminal,
            let keyEncoder
        else {
            throw GhosttyVTError.unavailable
        }

        var keyEvent: GhosttyKeyEvent?
        try Self.check(
            ghostty_key_event_new(nil, &keyEvent)
        )
        guard let keyEvent else {
            throw GhosttyVTError.unavailable
        }
        defer { ghostty_key_event_free(keyEvent) }

        ghostty_key_encoder_setopt_from_terminal(keyEncoder, terminal)
        ghostty_key_event_set_action(keyEvent, Self.keyAction(for: event.action))
        ghostty_key_event_set_key(keyEvent, Self.key(for: event.keyCode))
        ghostty_key_event_set_mods(keyEvent, Self.mods(for: event.modifiers))
        // Compute consumed modifiers: Shift is consumed for printable keys
        // (matching ghostling/main.c:540-548 algorithm)
        var consumedMods: GhosttyMods = 0
        if let unshiftedScalar = event.unshiftedText?.unicodeScalars.first,
           unshiftedScalar.value != 0,
           event.modifiers.contains(.shift) {
            consumedMods = GhosttyMods(GHOSTTY_MODS_SHIFT)
        }
        ghostty_key_event_set_consumed_mods(keyEvent, consumedMods)
        ghostty_key_event_set_composing(keyEvent, event.composing)

        let text = event.text
        let result = try text.withCString { cString in
            if text.isEmpty {
                ghostty_key_event_set_utf8(keyEvent, nil, 0)
            } else {
                ghostty_key_event_set_utf8(keyEvent, cString, text.utf8.count)
            }

            if let unshiftedScalar = event.unshiftedText?.unicodeScalars.first {
                ghostty_key_event_set_unshifted_codepoint(keyEvent, unshiftedScalar.value)
            } else {
                ghostty_key_event_set_unshifted_codepoint(keyEvent, 0)
            }

            return try Self.encode { buffer, bufferLength, written in
                ghostty_key_encoder_encode(
                    keyEncoder,
                    keyEvent,
                    buffer,
                    bufferLength,
                    written
                )
            }
        }

        return result
    }

    public func encodeMouse(_ event: GhosttyVTMouseEventDescriptor) throws -> Data? {
        guard
            let terminal,
            let mouseEncoder
        else {
            throw GhosttyVTError.unavailable
        }

        var mouseEvent: GhosttyMouseEvent?
        try Self.check(
            ghostty_mouse_event_new(nil, &mouseEvent)
        )
        guard let mouseEvent else {
            throw GhosttyVTError.unavailable
        }
        defer { ghostty_mouse_event_free(mouseEvent) }

        ghostty_mouse_encoder_setopt_from_terminal(mouseEncoder, terminal)

        var size = GhosttyMouseEncoderSize()
        size.size = numericCast(MemoryLayout<GhosttyMouseEncoderSize>.size)
        size.screen_width = numericCast(max(0, event.sizeContext.screenWidth))
        size.screen_height = numericCast(max(0, event.sizeContext.screenHeight))
        size.cell_width = numericCast(max(1, event.sizeContext.cellWidth))
        size.cell_height = numericCast(max(1, event.sizeContext.cellHeight))
        size.padding_top = numericCast(max(0, event.sizeContext.paddingTop))
        size.padding_bottom = numericCast(max(0, event.sizeContext.paddingBottom))
        size.padding_right = numericCast(max(0, event.sizeContext.paddingRight))
        size.padding_left = numericCast(max(0, event.sizeContext.paddingLeft))
        ghostty_mouse_encoder_setopt(
            mouseEncoder,
            GHOSTTY_MOUSE_ENCODER_OPT_SIZE,
            &size
        )

        var trackLastCell = true
        ghostty_mouse_encoder_setopt(
            mouseEncoder,
            GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL,
            &trackLastCell
        )
        var anyButtonPressed = anyMouseButtonPressed
        ghostty_mouse_encoder_setopt(
            mouseEncoder,
            GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED,
            &anyButtonPressed
        )

        ghostty_mouse_event_set_action(mouseEvent, Self.mouseAction(for: event.action))
        if let button = event.button {
            ghostty_mouse_event_set_button(mouseEvent, Self.mouseButton(for: button))
        } else {
            ghostty_mouse_event_clear_button(mouseEvent)
        }
        ghostty_mouse_event_set_mods(mouseEvent, Self.mods(for: event.modifiers))
        ghostty_mouse_event_set_position(
            mouseEvent,
            GhosttyMousePosition(
                x: Float(event.position.x),
                y: Float(event.position.y)
            )
        )

        let encoded = try Self.encode { buffer, bufferLength, written in
            ghostty_mouse_encoder_encode(
                mouseEncoder,
                mouseEvent,
                buffer,
                bufferLength,
                written
            )
        }

        switch event.action {
        case .press:
            anyMouseButtonPressed = true
        case .release:
            anyMouseButtonPressed = false
        case .motion:
            break
        }

        return encoded
    }

    public func encodeFocus(_ focused: Bool) throws -> Data? {
        guard try modeIsEnabled(Self.focusEventMode) else {
            return nil
        }

        return try Self.encode { buffer, bufferLength, written in
            ghostty_focus_encode(
                focused ? GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST,
                buffer,
                bufferLength,
                written
            )
        }
    }

    public func encodePaste(_ data: Data) throws -> Data? {
        guard let terminal else {
            throw GhosttyVTError.unavailable
        }
        guard !data.isEmpty else { return nil }

        if try modeIsEnabled(Self.bracketedPasteMode) {
            var wrapped = Data("\u{1B}[200~".utf8)
            wrapped.append(data)
            wrapped.append(Data("\u{1B}[201~".utf8))
            return wrapped
        }

        let safe = data.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return true
            }
            return ghostty_paste_is_safe(baseAddress, rawBuffer.count)
        }

        if safe {
            return data
        }

        if try modeIsEnabled(Self.altSendsEscapeMode) {
            return data
        }

        _ = terminal
        return nil
    }

    public func encodeInBandResizeReport(
        pixelSize: TerminalPixelSize,
        cellPixelSize: TerminalPixelSize
    ) throws -> Data? {
        guard try modeIsEnabled(Self.inBandResizeMode) else {
            return nil
        }

        let size = try currentSize()
        let reportSize = GhosttySizeReportSize(
            rows: numericCast(size.rows),
            columns: numericCast(size.columns),
            cell_width: numericCast(max(1, cellPixelSize.width)),
            cell_height: numericCast(max(1, cellPixelSize.height))
        )
        _ = pixelSize

        return try Self.encode { buffer, bufferLength, written in
            ghostty_size_report_encode(
                GHOSTTY_SIZE_REPORT_MODE_2048,
                reportSize,
                buffer,
                bufferLength,
                written
            )
        }
    }

    public func interactionCapabilities() throws -> GhosttyVTInteractionCapabilities {
        let supportsMouseReporting = try modeIsEnabled(Self.mouseButtonEventMode)
            || modeIsEnabled(Self.mouseDragEventMode)
            || modeIsEnabled(Self.mouseMotionEventMode)
        return GhosttyVTInteractionCapabilities(
            supportsMousePlacement: supportsMouseReporting,
            supportsScrollReporting: supportsMouseReporting
        )
    }

    public func refreshRenderState() throws {
        guard let terminal, let renderState else {
            throw GhosttyVTError.unavailable
        }
        try Self.check(
            ghostty_render_state_update(renderState, terminal)
        )
    }

    public func snapshotProjection(clearDirty: Bool = false) throws -> GhosttyVTRenderProjection {
        guard
            let terminal,
            let renderState,
            let rowIterator,
            let rowCells
        else {
            throw GhosttyVTError.unavailable
        }

        try refreshRenderState()

        let columns = Int(try value(for: GHOSTTY_RENDER_STATE_DATA_COLS, default: UInt16(options.columns)))
        let rows = Int(try value(for: GHOSTTY_RENDER_STATE_DATA_ROWS, default: UInt16(options.rows)))
        let dirtyStateValue = try value(
            for: GHOSTTY_RENDER_STATE_DATA_DIRTY,
            default: GHOSTTY_RENDER_STATE_DIRTY_FULL
        )
        let dirtyState = Self.dirtyState(for: dirtyStateValue)

        var colors = GhosttyRenderStateColors()
        colors.size = numericCast(MemoryLayout<GhosttyRenderStateColors>.size)
        try Self.check(
            ghostty_render_state_colors_get(renderState, &colors)
        )

        var populatedRowIterator = rowIterator
        try Self.check(
            withUnsafeMutablePointer(to: &populatedRowIterator) { iteratorPointer in
                ghostty_render_state_get(
                    renderState,
                    GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                    iteratorPointer
                )
            }
        )

        var projectionRows: [GhosttyVTRowProjection] = []
        projectionRows.reserveCapacity(rows)
        var dirtyRows: [Int] = []
        var rowIndex = 0
        var populatedRowCells = rowCells

        while ghostty_render_state_row_iterator_next(populatedRowIterator) {
            let isDirty = try rowValue(
                iterator: populatedRowIterator,
                data: GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY,
                default: false
            )
            let rawRow = try rowValue(
                iterator: populatedRowIterator,
                data: GHOSTTY_RENDER_STATE_ROW_DATA_RAW,
                default: GhosttyRow()
            )
            let wrapped = try Self.rowInfo(rawRow, GHOSTTY_ROW_DATA_WRAP, default: false)
            let wrapContinuation = try Self.rowInfo(rawRow, GHOSTTY_ROW_DATA_WRAP_CONTINUATION, default: false)

            try Self.check(
                withUnsafeMutablePointer(to: &populatedRowCells) { cellsPointer in
                    ghostty_render_state_row_get(
                        populatedRowIterator,
                        GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                        cellsPointer
                    )
                }
            )

            var cells: [GhosttyVTCellProjection] = []
            cells.reserveCapacity(columns)
            var columnIndex = 0
            while ghostty_render_state_row_cells_next(populatedRowCells) {
                let rawCell = try cellValue(
                    cells: populatedRowCells,
                    data: GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW,
                    default: GhosttyCell()
                )
                var style = GhosttyStyle()
                style.size = numericCast(MemoryLayout<GhosttyStyle>.size)
                try Self.check(
                    ghostty_render_state_row_cells_get(
                        populatedRowCells,
                        GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
                        &style
                    )
                )

                let graphemeLength = Int(try cellValue(
                    cells: populatedRowCells,
                    data: GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
                    default: UInt32(0)
                ))
                let text: String
                if graphemeLength > 0 {
                    var graphemes = Array(repeating: UInt32(0), count: graphemeLength)
                    try graphemes.withUnsafeMutableBufferPointer { buffer in
                        try Self.check(
                            ghostty_render_state_row_cells_get(
                                populatedRowCells,
                                GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                                buffer.baseAddress
                            )
                        )
                    }
                    text = Self.string(from: graphemes)
                } else {
                    text = ""
                }

                let wide = try Self.cellInfo(rawCell, GHOSTTY_CELL_DATA_WIDE, default: GHOSTTY_CELL_WIDE_NARROW)
                cells.append(
                    GhosttyVTCellProjection(
                        column: columnIndex,
                        text: text,
                        style: Self.styleProjection(from: style),
                        width: Self.cellWidth(for: wide)
                    )
                )
                columnIndex += 1
            }

            if isDirty {
                dirtyRows.append(rowIndex)
                if clearDirty {
                    var clean = false
                    try Self.check(
                        ghostty_render_state_row_set(
                            populatedRowIterator,
                            GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY,
                            &clean
                        )
                    )
                }
            }

            projectionRows.append(
                GhosttyVTRowProjection(
                    index: rowIndex,
                    dirty: isDirty,
                    wrapped: wrapped,
                    wrapContinuation: wrapContinuation,
                    cells: cells
                )
            )
            rowIndex += 1
        }

        let cursor = GhosttyVTCursorProjection(
            visualStyle: Self.cursorStyle(try value(
                for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE,
                default: GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK
            )),
            visible: try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, default: true),
            blinking: try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING, default: false),
            passwordInput: try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_PASSWORD_INPUT, default: false),
            x: try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, default: false)
                ? Int(try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, default: UInt16(0)))
                : nil,
            y: try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, default: false)
                ? Int(try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, default: UInt16(0)))
                : nil,
            wideTail: try value(for: GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL, default: false)
        )

        let scrollbar = try Self.terminalValue(
            terminal,
            data: GHOSTTY_TERMINAL_DATA_SCROLLBAR,
            default: GhosttyTerminalScrollbar()
        )
        let scrollbarProjection = scrollbar.total > 0
            ? GhosttyVTScrollbarProjection(
                total: scrollbar.total,
                offset: scrollbar.offset,
                length: scrollbar.len
            )
            : nil

        if clearDirty {
            var cleanState = GHOSTTY_RENDER_STATE_DIRTY_FALSE
            try Self.check(
                ghostty_render_state_set(
                    renderState,
                    GHOSTTY_RENDER_STATE_OPTION_DIRTY,
                    &cleanState
                )
            )
        }

        let resolvedTheme = Self.resolveThemeColors(from: colors)

        return GhosttyVTRenderProjection(
            columns: columns,
            rows: rows,
            dirtyState: dirtyState,
            dirtyRows: dirtyRows,
            backgroundColor: resolvedTheme.background,
            foregroundColor: resolvedTheme.foreground,
            cursorColor: resolvedTheme.cursor,
            palette: resolvedTheme.palette,
            cursor: cursor,
            rowsProjection: projectionRows,
            scrollbar: scrollbarProjection
        )
    }

    public func withTerminal<T>(_ body: (GhosttyTerminal) throws -> T) rethrows -> T? {
        guard let terminal else { return nil }
        return try body(terminal)
    }

    public func withRenderState<T>(_ body: (GhosttyRenderState) throws -> T) rethrows -> T? {
        guard let renderState else { return nil }
        return try body(renderState)
    }

    private func modeIsEnabled(_ mode: GhosttyMode) throws -> Bool {
        guard let terminal else {
            throw GhosttyVTError.unavailable
        }
        var value = false
        try Self.check(
            ghostty_terminal_mode_get(terminal, mode, &value)
        )
        return value
    }

    private func value(
        for data: GhosttyRenderStateData,
        default defaultValue: Bool
    ) throws -> Bool {
        guard let renderState else {
            throw GhosttyVTError.unavailable
        }
        var value = defaultValue
        let result = ghostty_render_state_get(renderState, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func value(
        for data: GhosttyRenderStateData,
        default defaultValue: UInt16
    ) throws -> UInt16 {
        guard let renderState else {
            throw GhosttyVTError.unavailable
        }
        var value = defaultValue
        let result = ghostty_render_state_get(renderState, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func value(
        for data: GhosttyRenderStateData,
        default defaultValue: GhosttyRenderStateDirty
    ) throws -> GhosttyRenderStateDirty {
        guard let renderState else {
            throw GhosttyVTError.unavailable
        }
        var value = defaultValue
        let result = ghostty_render_state_get(renderState, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func value(
        for data: GhosttyRenderStateData,
        default defaultValue: GhosttyRenderStateCursorVisualStyle
    ) throws -> GhosttyRenderStateCursorVisualStyle {
        guard let renderState else {
            throw GhosttyVTError.unavailable
        }
        var value = defaultValue
        let result = ghostty_render_state_get(renderState, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func rowValue(
        iterator: GhosttyRenderStateRowIterator,
        data: GhosttyRenderStateRowData,
        default defaultValue: Bool
    ) throws -> Bool {
        var value = defaultValue
        let result = ghostty_render_state_row_get(iterator, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func rowValue(
        iterator: GhosttyRenderStateRowIterator,
        data: GhosttyRenderStateRowData,
        default defaultValue: GhosttyRow
    ) throws -> GhosttyRow {
        var value = defaultValue
        let result = ghostty_render_state_row_get(iterator, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func cellValue(
        cells: GhosttyRenderStateRowCells,
        data: GhosttyRenderStateRowCellsData,
        default defaultValue: UInt32
    ) throws -> UInt32 {
        var value = defaultValue
        let result = ghostty_render_state_row_cells_get(cells, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private func cellValue(
        cells: GhosttyRenderStateRowCells,
        data: GhosttyRenderStateRowCellsData,
        default defaultValue: GhosttyCell
    ) throws -> GhosttyCell {
        var value = defaultValue
        let result = ghostty_render_state_row_cells_get(cells, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private static func terminalValue(
        _ terminal: GhosttyTerminal,
        data: GhosttyTerminalData,
        default defaultValue: UInt16
    ) throws -> UInt16 {
        var value = defaultValue
        let result = ghostty_terminal_get(terminal, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private static func terminalValue(
        _ terminal: GhosttyTerminal,
        data: GhosttyTerminalData,
        default defaultValue: GhosttyTerminalScrollbar
    ) throws -> GhosttyTerminalScrollbar {
        var value = defaultValue
        let result = ghostty_terminal_get(terminal, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private static func rowInfo(
        _ row: GhosttyRow,
        _ data: GhosttyRowData,
        default defaultValue: Bool
    ) throws -> Bool {
        var value = defaultValue
        let result = ghostty_row_get(row, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private static func cellInfo(
        _ cell: GhosttyCell,
        _ data: GhosttyCellData,
        default defaultValue: GhosttyCellWide
    ) throws -> GhosttyCellWide {
        var value = defaultValue
        let result = ghostty_cell_get(cell, data, &value)
        if result == GHOSTTY_INVALID_VALUE {
            return defaultValue
        }
        try Self.check(result)
        return value
    }

    private static func check(_ result: GhosttyResult) throws {
        guard result == GHOSTTY_SUCCESS else {
            throw GhosttyVTError.operationFailed(result.rawValue)
        }
    }

    private static func encode(
        _ body: (_ buffer: UnsafeMutablePointer<CChar>?, _ bufferLength: Int, _ written: UnsafeMutablePointer<Int>?) -> GhosttyResult
    ) throws -> Data? {
        var requiredLength = 0
        var probe = body(nil, 0, &requiredLength)
        if probe == GHOSTTY_SUCCESS {
            return requiredLength == 0 ? nil : Data()
        }
        if probe != GHOSTTY_OUT_OF_SPACE {
            try check(probe)
        }

        var buffer = Array<CChar>(repeating: 0, count: max(1, requiredLength))
        var written = 0
        probe = body(&buffer, buffer.count, &written)
        try check(probe)
        guard written > 0 else { return nil }
        return Data(bytes: buffer, count: written)
    }

    private static func keyAction(for action: GhosttyVTKeyAction) -> GhosttyKeyAction {
        switch action {
        case .press: return GHOSTTY_KEY_ACTION_PRESS
        case .release: return GHOSTTY_KEY_ACTION_RELEASE
        case .repeat: return GHOSTTY_KEY_ACTION_REPEAT
        }
    }

    private static func mouseAction(for action: GhosttyVTMouseAction) -> GhosttyMouseAction {
        switch action {
        case .press: return GHOSTTY_MOUSE_ACTION_PRESS
        case .release: return GHOSTTY_MOUSE_ACTION_RELEASE
        case .motion: return GHOSTTY_MOUSE_ACTION_MOTION
        }
    }

    private static func mouseButton(for button: GhosttyVTMouseButton) -> GhosttyMouseButton {
        switch button {
        case .left: return GHOSTTY_MOUSE_BUTTON_LEFT
        case .right: return GHOSTTY_MOUSE_BUTTON_RIGHT
        case .middle: return GHOSTTY_MOUSE_BUTTON_MIDDLE
        case .button4: return GHOSTTY_MOUSE_BUTTON_FOUR
        case .button5: return GHOSTTY_MOUSE_BUTTON_FIVE
        }
    }

    private static func mods(for modifiers: GhosttyVTModifiers) -> GhosttyMods {
        var result: UInt16 = 0
        if modifiers.contains(.shift) { result |= UInt16(GHOSTTY_MODS_SHIFT) }
        if modifiers.contains(.control) { result |= UInt16(GHOSTTY_MODS_CTRL) }
        if modifiers.contains(.alt) { result |= UInt16(GHOSTTY_MODS_ALT) }
        if modifiers.contains(.super) { result |= UInt16(GHOSTTY_MODS_SUPER) }
        if modifiers.contains(.capsLock) { result |= UInt16(GHOSTTY_MODS_CAPS_LOCK) }
        if modifiers.contains(.numLock) { result |= UInt16(GHOSTTY_MODS_NUM_LOCK) }
        return GhosttyMods(result)
    }

    private static func key(for keyCode: GhosttyVTKeyCode?) -> GhosttyKey {
        switch keyCode ?? .unidentified {
        case .unidentified: return GHOSTTY_KEY_UNIDENTIFIED
        case .backquote: return GHOSTTY_KEY_BACKQUOTE
        case .backslash: return GHOSTTY_KEY_BACKSLASH
        case .bracketLeft: return GHOSTTY_KEY_BRACKET_LEFT
        case .bracketRight: return GHOSTTY_KEY_BRACKET_RIGHT
        case .comma: return GHOSTTY_KEY_COMMA
        case .digit0: return GHOSTTY_KEY_DIGIT_0
        case .digit1: return GHOSTTY_KEY_DIGIT_1
        case .digit2: return GHOSTTY_KEY_DIGIT_2
        case .digit3: return GHOSTTY_KEY_DIGIT_3
        case .digit4: return GHOSTTY_KEY_DIGIT_4
        case .digit5: return GHOSTTY_KEY_DIGIT_5
        case .digit6: return GHOSTTY_KEY_DIGIT_6
        case .digit7: return GHOSTTY_KEY_DIGIT_7
        case .digit8: return GHOSTTY_KEY_DIGIT_8
        case .digit9: return GHOSTTY_KEY_DIGIT_9
        case .equal: return GHOSTTY_KEY_EQUAL
        case .a: return GHOSTTY_KEY_A
        case .b: return GHOSTTY_KEY_B
        case .c: return GHOSTTY_KEY_C
        case .d: return GHOSTTY_KEY_D
        case .e: return GHOSTTY_KEY_E
        case .f: return GHOSTTY_KEY_F
        case .g: return GHOSTTY_KEY_G
        case .h: return GHOSTTY_KEY_H
        case .i: return GHOSTTY_KEY_I
        case .j: return GHOSTTY_KEY_J
        case .k: return GHOSTTY_KEY_K
        case .l: return GHOSTTY_KEY_L
        case .m: return GHOSTTY_KEY_M
        case .n: return GHOSTTY_KEY_N
        case .o: return GHOSTTY_KEY_O
        case .p: return GHOSTTY_KEY_P
        case .q: return GHOSTTY_KEY_Q
        case .r: return GHOSTTY_KEY_R
        case .s: return GHOSTTY_KEY_S
        case .t: return GHOSTTY_KEY_T
        case .u: return GHOSTTY_KEY_U
        case .v: return GHOSTTY_KEY_V
        case .w: return GHOSTTY_KEY_W
        case .x: return GHOSTTY_KEY_X
        case .y: return GHOSTTY_KEY_Y
        case .z: return GHOSTTY_KEY_Z
        case .minus: return GHOSTTY_KEY_MINUS
        case .period: return GHOSTTY_KEY_PERIOD
        case .quote: return GHOSTTY_KEY_QUOTE
        case .semicolon: return GHOSTTY_KEY_SEMICOLON
        case .slash: return GHOSTTY_KEY_SLASH
        case .altLeft: return GHOSTTY_KEY_ALT_LEFT
        case .altRight: return GHOSTTY_KEY_ALT_RIGHT
        case .backspace: return GHOSTTY_KEY_BACKSPACE
        case .capsLock: return GHOSTTY_KEY_CAPS_LOCK
        case .controlLeft: return GHOSTTY_KEY_CONTROL_LEFT
        case .controlRight: return GHOSTTY_KEY_CONTROL_RIGHT
        case .enter: return GHOSTTY_KEY_ENTER
        case .metaLeft: return GHOSTTY_KEY_META_LEFT
        case .metaRight: return GHOSTTY_KEY_META_RIGHT
        case .shiftLeft: return GHOSTTY_KEY_SHIFT_LEFT
        case .shiftRight: return GHOSTTY_KEY_SHIFT_RIGHT
        case .space: return GHOSTTY_KEY_SPACE
        case .tab: return GHOSTTY_KEY_TAB
        case .delete: return GHOSTTY_KEY_DELETE
        case .end: return GHOSTTY_KEY_END
        case .home: return GHOSTTY_KEY_HOME
        case .insert: return GHOSTTY_KEY_INSERT
        case .pageDown: return GHOSTTY_KEY_PAGE_DOWN
        case .pageUp: return GHOSTTY_KEY_PAGE_UP
        case .arrowDown: return GHOSTTY_KEY_ARROW_DOWN
        case .arrowLeft: return GHOSTTY_KEY_ARROW_LEFT
        case .arrowRight: return GHOSTTY_KEY_ARROW_RIGHT
        case .arrowUp: return GHOSTTY_KEY_ARROW_UP
        case .escape: return GHOSTTY_KEY_ESCAPE
        case .f1: return GHOSTTY_KEY_F1
        case .f2: return GHOSTTY_KEY_F2
        case .f3: return GHOSTTY_KEY_F3
        case .f4: return GHOSTTY_KEY_F4
        case .f5: return GHOSTTY_KEY_F5
        case .f6: return GHOSTTY_KEY_F6
        case .f7: return GHOSTTY_KEY_F7
        case .f8: return GHOSTTY_KEY_F8
        case .f9: return GHOSTTY_KEY_F9
        case .f10: return GHOSTTY_KEY_F10
        case .f11: return GHOSTTY_KEY_F11
        case .f12: return GHOSTTY_KEY_F12
        }
    }

    private static func color(from color: GhosttyColorRgb) -> GhosttyVTColor {
        GhosttyVTColor(r: color.r, g: color.g, b: color.b)
    }

    private static func styleColor(from color: GhosttyStyleColor) -> GhosttyVTStyleColor {
        switch color.tag {
        case GHOSTTY_STYLE_COLOR_NONE:
            return .none
        case GHOSTTY_STYLE_COLOR_PALETTE:
            return .palette(color.value.palette)
        case GHOSTTY_STYLE_COLOR_RGB:
            return .rgb(Self.color(from: color.value.rgb))
        default:
            return .none
        }
    }

    private static func styleProjection(from style: GhosttyStyle) -> GhosttyVTTextStyle {
        GhosttyVTTextStyle(
            foreground: styleColor(from: style.fg_color),
            background: styleColor(from: style.bg_color),
            underlineColor: styleColor(from: style.underline_color),
            bold: style.bold,
            italic: style.italic,
            faint: style.faint,
            blink: style.blink,
            inverse: style.inverse,
            invisible: style.invisible,
            strikethrough: style.strikethrough,
            overline: style.overline,
            underline: Int(style.underline)
        )
    }

    private static let focusEventMode = ghostty_mode_new(1004, false)
    private static let mouseButtonEventMode = ghostty_mode_new(1000, false)
    private static let mouseDragEventMode = ghostty_mode_new(1002, false)
    private static let mouseMotionEventMode = ghostty_mode_new(1003, false)
    private static let altSendsEscapeMode = ghostty_mode_new(1039, false)
    private static let bracketedPasteMode = ghostty_mode_new(2004, false)
    private static let inBandResizeMode = ghostty_mode_new(2048, false)

    private static func paletteColors(from colors: GhosttyRenderStateColors) -> [GhosttyVTColor] {
        withUnsafePointer(to: colors.palette) { tuplePointer in
            let colorPointer = UnsafeRawPointer(tuplePointer).assumingMemoryBound(to: GhosttyColorRgb.self)
            return (0..<256).map { index in
                Self.color(from: colorPointer[index])
            }
        }
    }

    private static func resolveThemeColors(
        from colors: GhosttyRenderStateColors
    ) -> (background: GhosttyVTColor, foreground: GhosttyVTColor, cursor: GhosttyVTColor?, palette: [GhosttyVTColor]) {
        var background = Self.color(from: colors.background)
        var foreground = Self.color(from: colors.foreground)
        var palette = Self.paletteColors(from: colors)

        if background == foreground {
            background = Self.defaultTerminalBackground
            foreground = Self.defaultTerminalForeground
        }

        if Self.paletteNeedsFallback(palette) {
            palette = Self.defaultTerminalPalette
        }

        let cursor = colors.cursor_has_value ? Self.color(from: colors.cursor) : nil
        let resolvedCursor: GhosttyVTColor?
        if let cursor, cursor != background {
            resolvedCursor = cursor
        } else {
            resolvedCursor = nil
        }

        return (
            background: background,
            foreground: foreground,
            cursor: resolvedCursor,
            palette: palette
        )
    }

    private static func paletteNeedsFallback(_ palette: [GhosttyVTColor]) -> Bool {
        guard palette.count == 256 else { return true }
        let reference = palette[0]
        return palette.allSatisfy { $0 == reference }
    }

    private static let defaultTerminalBackground = GhosttyVTColor(r: 0, g: 0, b: 0)
    private static let defaultTerminalForeground = GhosttyVTColor(r: 229, g: 229, b: 229)
    private static let defaultTerminalPalette: [GhosttyVTColor] = {
        var palette: [GhosttyVTColor] = [
            GhosttyVTColor(r: 0, g: 0, b: 0),
            GhosttyVTColor(r: 205, g: 0, b: 0),
            GhosttyVTColor(r: 0, g: 205, b: 0),
            GhosttyVTColor(r: 205, g: 205, b: 0),
            GhosttyVTColor(r: 0, g: 0, b: 238),
            GhosttyVTColor(r: 205, g: 0, b: 205),
            GhosttyVTColor(r: 0, g: 205, b: 205),
            GhosttyVTColor(r: 229, g: 229, b: 229),
            GhosttyVTColor(r: 127, g: 127, b: 127),
            GhosttyVTColor(r: 255, g: 0, b: 0),
            GhosttyVTColor(r: 0, g: 255, b: 0),
            GhosttyVTColor(r: 255, g: 255, b: 0),
            GhosttyVTColor(r: 92, g: 92, b: 255),
            GhosttyVTColor(r: 255, g: 0, b: 255),
            GhosttyVTColor(r: 0, g: 255, b: 255),
            GhosttyVTColor(r: 255, g: 255, b: 255),
        ]

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

    private static func dirtyState(for dirty: GhosttyRenderStateDirty) -> GhosttyVTDirtyState {
        switch dirty {
        case GHOSTTY_RENDER_STATE_DIRTY_FALSE:
            return .clean
        case GHOSTTY_RENDER_STATE_DIRTY_PARTIAL:
            return .partial
        case GHOSTTY_RENDER_STATE_DIRTY_FULL:
            return .full
        default:
            return .full
        }
    }

    private static func cursorStyle(_ style: GhosttyRenderStateCursorVisualStyle) -> GhosttyVTCursorVisualStyle {
        switch style {
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR:
            return .bar
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE:
            return .underline
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW:
            return .hollowBlock
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK:
            fallthrough
        default:
            return .block
        }
    }

    private static func cellWidth(for wide: GhosttyCellWide) -> GhosttyVTCellWidth {
        switch wide {
        case GHOSTTY_CELL_WIDE_WIDE:
            return .wide
        case GHOSTTY_CELL_WIDE_SPACER_TAIL:
            return .spacerTail
        case GHOSTTY_CELL_WIDE_SPACER_HEAD:
            return .spacerHead
        case GHOSTTY_CELL_WIDE_NARROW:
            fallthrough
        default:
            return .narrow
        }
    }

    private static func string(from graphemes: [UInt32]) -> String {
        let scalars = graphemes.compactMap(UnicodeScalar.init)
        return String(String.UnicodeScalarView(scalars))
    }
}
#else
public enum GhosttyVTBindings {
    public static let isLinked = false
}

public struct GhosttyVTTerminalOptions: Sendable {
    public var columns: UInt16
    public var rows: UInt16
    public var scrollbackLines: Int

    public init(
        columns: UInt16 = 80,
        rows: UInt16 = 24,
        scrollbackLines: Int = 10_000
    ) {
        self.columns = columns
        self.rows = rows
        self.scrollbackLines = scrollbackLines
    }
}

public enum GhosttyVTError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "CGhosttyVT is unavailable for the current build."
    }
}

public final class GhosttyVTTerminalEngine {
    public let options: GhosttyVTTerminalOptions

    public init(options: GhosttyVTTerminalOptions = GhosttyVTTerminalOptions()) throws {
        self.options = options
        throw GhosttyVTError.unavailable
    }

    public func write(_ data: Data) {}
    public func resize(columns: UInt16, rows: UInt16) throws {
        throw GhosttyVTError.unavailable
    }
    public func scrollViewport(delta: Int) {}
    public func currentSize() throws -> TerminalSize {
        throw GhosttyVTError.unavailable
    }
    public func encodeKey(_ event: GhosttyVTKeyEventDescriptor) throws -> Data? {
        throw GhosttyVTError.unavailable
    }
    public func encodeMouse(_ event: GhosttyVTMouseEventDescriptor) throws -> Data? {
        throw GhosttyVTError.unavailable
    }
    public func encodeFocus(_ focused: Bool) throws -> Data? {
        throw GhosttyVTError.unavailable
    }
    public func encodePaste(_ data: Data) throws -> Data? {
        throw GhosttyVTError.unavailable
    }
    public func encodeInBandResizeReport(
        pixelSize: TerminalPixelSize,
        cellPixelSize: TerminalPixelSize
    ) throws -> Data? {
        throw GhosttyVTError.unavailable
    }
    public func interactionCapabilities() throws -> GhosttyVTInteractionCapabilities {
        GhosttyVTInteractionCapabilities(
            supportsMousePlacement: false,
            supportsScrollReporting: false
        )
    }
    public func refreshRenderState() throws {
        throw GhosttyVTError.unavailable
    }
    public func snapshotProjection(clearDirty: Bool = false) throws -> GhosttyVTRenderProjection {
        throw GhosttyVTError.unavailable
    }
}
#endif
