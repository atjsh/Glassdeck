import Foundation

/// Coordinates input from all sources (keyboard, mouse/trackpad, on-screen)
/// and dispatches to the active terminal session.
@Observable
final class InputCoordinator {
    let keyboardHandler = KeyboardInputHandler()
    let pointerHandler = PointerInputHandler()

    private weak var activeTerminal: TerminalInputDelegate?

    /// Set the active terminal that receives input.
    func setActiveTerminal(_ terminal: TerminalInputDelegate) {
        activeTerminal = terminal
        keyboardHandler.terminalResponder = terminal
        pointerHandler.terminalResponder = terminal
    }

    /// Forward raw data to the active terminal.
    func sendInput(_ data: Data) {
        activeTerminal?.didReceiveInput(data)
    }

    /// Forward a string as UTF-8 data to the active terminal.
    func sendText(_ text: String) {
        sendInput(Data(text.utf8))
    }
}
