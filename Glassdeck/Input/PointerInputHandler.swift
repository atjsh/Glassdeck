import UIKit

/// Handles mouse and trackpad input for the terminal.
///
/// Uses UIPointerInteraction for cursor visibility and hover effects.
/// Forwards mouse clicks, scroll events, and drag gestures to the terminal
/// using SGR mouse reporting mode.
final class PointerInputHandler: NSObject, UIPointerInteractionDelegate {

    weak var terminalResponder: TerminalInputDelegate?

    /// Create a UIPointerInteraction for the terminal view.
    func makePointerInteraction() -> UIPointerInteraction {
        UIPointerInteraction(delegate: self)
    }

    // MARK: - UIPointerInteractionDelegate

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        regionFor request: UIPointerRegionRequest,
        defaultRegion: UIPointerRegion
    ) -> UIPointerRegion? {
        // Return the full view as a pointer region
        return defaultRegion
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        // Use a text cursor (I-beam) style for the terminal
        return UIPointerStyle(shape: .verticalBeam(length: 20))
    }

    // MARK: - SGR Mouse Encoding

    /// Encode a mouse event in SGR format for terminal mouse reporting.
    ///
    /// SGR format: ESC [ < Cb ; Cx ; Cy M (press) or m (release)
    func sgrMouseEvent(
        button: MouseButton,
        action: MouseAction,
        column: Int,
        row: Int,
        modifiers: UIKeyModifierFlags = []
    ) -> Data {
        var cb = button.rawValue

        if modifiers.contains(.shift) { cb |= 4 }
        if modifiers.contains(.alternate) { cb |= 8 }
        if modifiers.contains(.control) { cb |= 16 }

        let suffix = action == .press ? "M" : "m"
        let sequence = "\u{1b}[<\(cb);\(column);\(row)\(suffix)"
        return Data(sequence.utf8)
    }

    /// Encode a scroll event in SGR format.
    func sgrScrollEvent(
        direction: ScrollDirection,
        column: Int,
        row: Int
    ) -> Data {
        let cb = direction == .up ? 64 : 65
        let sequence = "\u{1b}[<\(cb);\(column);\(row)M"
        return Data(sequence.utf8)
    }

    enum MouseButton: Int {
        case left = 0
        case middle = 1
        case right = 2
    }

    enum MouseAction {
        case press
        case release
    }

    enum ScrollDirection {
        case up
        case down
    }
}
