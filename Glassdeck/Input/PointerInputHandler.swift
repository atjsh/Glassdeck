#if canImport(UIKit)
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
}
#endif
