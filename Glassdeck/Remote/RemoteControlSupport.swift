#if canImport(UIKit)
import CoreGraphics
import Foundation
import GlassdeckCore

struct RemoteControlInsets: Sendable, Equatable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int

    static let zero = RemoteControlInsets(top: 0, left: 0, bottom: 0, right: 0)
}

struct RemoteTerminalGeometry: Sendable, Equatable {
    var terminalSize: TerminalSize
    var surfacePixelSize: TerminalPixelSize
    var cellPixelSize: TerminalPixelSize
    var padding: RemoteControlInsets
    var displayScale: Double

    static let zero = RemoteTerminalGeometry(
        terminalSize: TerminalSize(columns: 80, rows: 24),
        surfacePixelSize: TerminalPixelSize(width: 0, height: 0),
        cellPixelSize: TerminalPixelSize(width: 0, height: 0),
        padding: .zero,
        displayScale: 1
    )

    var viewportWidth: Int {
        max(0, surfacePixelSize.width - padding.left - padding.right)
    }

    var viewportHeight: Int {
        max(0, surfacePixelSize.height - padding.top - padding.bottom)
    }

    var isUsable: Bool {
        surfacePixelSize.width > 0
            && surfacePixelSize.height > 0
            && cellPixelSize.width > 0
            && cellPixelSize.height > 0
    }

    func clampedSurfacePixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(point.x, Double(max(0, surfacePixelSize.width - 1)))),
            y: max(0, min(point.y, Double(max(0, surfacePixelSize.height - 1))))
        )
    }

    func clampedViewportPixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(Double(padding.left), min(point.x, Double(max(padding.left, surfacePixelSize.width - padding.right - 1)))),
            y: max(Double(padding.top), min(point.y, Double(max(padding.top, surfacePixelSize.height - padding.bottom - 1))))
        )
    }

    func viewportPixelPoint(forFraction point: CGPoint) -> CGPoint {
        guard isUsable else { return .zero }
        let x = Double(padding.left) + max(0, min(point.x, 1)) * Double(viewportWidth)
        let y = Double(padding.top) + max(0, min(point.y, 1)) * Double(viewportHeight)
        return clampedViewportPixelPoint(CGPoint(x: x, y: y))
    }

    func cellPosition(forSurfacePixelPoint point: CGPoint) -> RemoteCellPosition? {
        guard isUsable else { return nil }
        let clamped = clampedViewportPixelPoint(point)
        let column = Int((clamped.x - Double(padding.left)) / Double(cellPixelSize.width))
        let row = Int((clamped.y - Double(padding.top)) / Double(cellPixelSize.height))
        guard terminalSize.columns > 0, terminalSize.rows > 0 else { return nil }
        return RemoteCellPosition(
            column: max(0, min(column, terminalSize.columns - 1)),
            row: max(0, min(row, terminalSize.rows - 1))
        )
    }

    func surfacePixelPoint(for cell: RemoteCellPosition) -> CGPoint {
        let column = max(0, min(cell.column, max(0, terminalSize.columns - 1)))
        let row = max(0, min(cell.row, max(0, terminalSize.rows - 1)))
        let x = Double(padding.left + (column * cellPixelSize.width) + (cellPixelSize.width / 2))
        let y = Double(padding.top + (row * cellPixelSize.height) + (cellPixelSize.height / 2))
        return clampedViewportPixelPoint(CGPoint(x: x, y: y))
    }

    func viewPoint(forSurfacePixelPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / max(displayScale, 1),
            y: point.y / max(displayScale, 1)
        )
    }

    func viewRect(for cell: RemoteCellPosition) -> CGRect {
        let origin = CGPoint(
            x: Double(padding.left + (cell.column * cellPixelSize.width)) / max(displayScale, 1),
            y: Double(padding.top + (cell.row * cellPixelSize.height)) / max(displayScale, 1)
        )
        return CGRect(
            origin: origin,
            size: CGSize(
                width: Double(cellPixelSize.width) / max(displayScale, 1),
                height: Double(cellPixelSize.height) / max(displayScale, 1)
            )
        )
    }
}

struct RemoteCellPosition: Sendable, Equatable {
    var column: Int
    var row: Int
}

struct RemotePointerOverlayState: Sendable, Equatable {
    var mode: RemoteControlMode
    var surfacePixelPoint: CGPoint
    var cellPosition: RemoteCellPosition?
    var isVisible: Bool
    var isDragging: Bool

    static let hidden = RemotePointerOverlayState(
        mode: .cursor,
        surfacePixelPoint: .zero,
        cellPosition: nil,
        isVisible: false,
        isDragging: false
    )
}
#endif
