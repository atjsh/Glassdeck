import Foundation
import UIKit

/// Handles external keyboard input and forwards key events to the terminal.
///
/// Uses UIKeyCommand responder chain to capture hardware key events
/// including modifier keys (Ctrl, Alt/Option, Cmd), arrow keys, and function keys.
@MainActor
final class KeyboardInputHandler {
    weak var terminalResponder: TerminalInputDelegate?

    /// All key commands this handler responds to.
    var keyCommands: [UIKeyCommand] {
        var commands: [UIKeyCommand] = []

        // Ctrl + letter keys (a-z)
        for char in "abcdefghijklmnopqrstuvwxyz" {
            commands.append(
                UIKeyCommand(
                    input: String(char),
                    modifierFlags: .control,
                    action: #selector(UIResponder.handleKeyCommand(_:))
                )
            )
        }

        // Arrow keys (with and without modifiers)
        let arrows = [
            UIKeyCommand.inputUpArrow,
            UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputLeftArrow,
            UIKeyCommand.inputRightArrow,
        ]
        for arrow in arrows {
            commands.append(
                UIKeyCommand(
                    input: arrow,
                    modifierFlags: [],
                    action: #selector(UIResponder.handleKeyCommand(_:))
                )
            )
            // With Shift
            commands.append(
                UIKeyCommand(
                    input: arrow,
                    modifierFlags: .shift,
                    action: #selector(UIResponder.handleKeyCommand(_:))
                )
            )
            // With Alt
            commands.append(
                UIKeyCommand(
                    input: arrow,
                    modifierFlags: .alternate,
                    action: #selector(UIResponder.handleKeyCommand(_:))
                )
            )
        }

        // Function keys
        let functionKeys = [
            UIKeyCommand.inputEscape,
            UIKeyCommand.inputPageUp,
            UIKeyCommand.inputPageDown,
            UIKeyCommand.inputHome,
            UIKeyCommand.inputEnd,
        ]
        for key in functionKeys {
            commands.append(
                UIKeyCommand(
                    input: key,
                    modifierFlags: [],
                    action: #selector(UIResponder.handleKeyCommand(_:))
                )
            )
        }

        // Tab
        commands.append(
            UIKeyCommand(
                input: "\t",
                modifierFlags: [],
                action: #selector(UIResponder.handleKeyCommand(_:))
            )
        )

        return commands
    }

    /// Convert a UIKeyCommand to terminal escape sequence data.
    func terminalData(for command: UIKeyCommand) -> Data? {
        // Ctrl + letter → send control character (ASCII 1-26)
        if command.modifierFlags.contains(.control),
           let input = command.input,
           let char = input.first,
           char.isLetter {
            let controlChar = UInt8(char.asciiValue! - 96) // 'a' = 1, 'b' = 2, etc.
            return Data([controlChar])
        }

        // Arrow keys
        switch command.input {
        case UIKeyCommand.inputUpArrow: return Data("\u{1b}[A".utf8)
        case UIKeyCommand.inputDownArrow: return Data("\u{1b}[B".utf8)
        case UIKeyCommand.inputRightArrow: return Data("\u{1b}[C".utf8)
        case UIKeyCommand.inputLeftArrow: return Data("\u{1b}[D".utf8)
        case UIKeyCommand.inputHome: return Data("\u{1b}[H".utf8)
        case UIKeyCommand.inputEnd: return Data("\u{1b}[F".utf8)
        case UIKeyCommand.inputPageUp: return Data("\u{1b}[5~".utf8)
        case UIKeyCommand.inputPageDown: return Data("\u{1b}[6~".utf8)
        case UIKeyCommand.inputEscape: return Data([0x1b])
        case "\t": return Data([0x09])
        default: break
        }

        // Regular character input
        if let input = command.input {
            return Data(input.utf8)
        }

        return nil
    }
}

/// Protocol for receiving terminal input from hardware peripherals.
protocol TerminalInputDelegate: AnyObject {
    func didReceiveInput(_ data: Data)
}

extension UIResponder {
    @objc func handleKeyCommand(_ command: UIKeyCommand) {
        // Forwarded by subclasses that implement keyboard handling
    }
}
