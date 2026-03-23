import SwiftUI
import UIKit

struct SessionKeyboardInputHost: UIViewRepresentable {
    let session: SSHSessionModel
    let isFocused: Bool
    let softwareKeyboardPresented: Bool

    func makeUIView(context: Context) -> SessionKeyboardHostView {
        SessionKeyboardHostView()
    }

    func updateUIView(_ uiView: SessionKeyboardHostView, context: Context) {
        uiView.update(
            surface: session.surface,
            isFocused: isFocused,
            softwareKeyboardPresented: softwareKeyboardPresented
        )
    }
}

final class SessionKeyboardHostView: UITextField {
    private static let debugTerminalInput = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private weak var surface: GhosttySurface?
    private let suppressedInputView = UIView(frame: .zero)
    private var softwareKeyboardPresented = false
    private var suppressTextForwarding = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        autocorrectionType = .no
        spellCheckingType = .no
        autocapitalizationType = .none
        textContentType = .none
        keyboardType = .asciiCapable
        smartDashesType = .no
        smartInsertDeleteType = .no
        smartQuotesType = .no
        tintColor = .clear
        textColor = .clear
        borderStyle = .none
        text = ""
        inputView = suppressedInputView
        accessibilityIdentifier = "session-keyboard-host"
        accessibilityLabel = "Software Keyboard Host"
        accessibilityTraits.insert(.playsSound)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var text: String? {
        didSet {
            guard !suppressTextForwarding else { return }
            forwardTextDelta(from: oldValue ?? "", to: text ?? "")
        }
    }

    func update(surface: GhosttySurface?, isFocused: Bool, softwareKeyboardPresented: Bool) {
        if self.surface !== surface {
            suppressTextForwarding = true
            text = ""
            suppressTextForwarding = false
        }
        self.surface = surface

        if self.softwareKeyboardPresented != softwareKeyboardPresented {
            self.softwareKeyboardPresented = softwareKeyboardPresented
            inputView = softwareKeyboardPresented ? nil : suppressedInputView
            debugLog("softwareKeyboardPresented=\(softwareKeyboardPresented)")
            reloadInputViews()
        }

        accessibilityValue = softwareKeyboardPresented ? "presented" : "hidden"

        if isFocused {
            if !isFirstResponder {
                becomeFirstResponder()
            }
        } else if isFirstResponder {
            resignFirstResponder()
        }
    }

    override func paste(_ sender: Any?) {
        surface?.paste(sender)
    }

    override func accessibilityActivate() -> Bool {
        captureKeyboardFocusIfNeeded()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = surface?.handleHardwarePresses(presses, action: .press) ?? presses
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = surface?.handleHardwarePresses(presses, action: .release) ?? presses
        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = surface?.handleHardwarePresses(presses, action: .release) ?? presses
        if !unhandled.isEmpty {
            super.pressesCancelled(unhandled, with: event)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = captureKeyboardFocusIfNeeded()
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = captureKeyboardFocusIfNeeded()
        super.touchesEnded(touches, with: event)
    }

    @discardableResult
    private func captureKeyboardFocusIfNeeded() -> Bool {
        if isFirstResponder {
            return true
        }
        return becomeFirstResponder()
    }

    override func insertText(_ text: String) {
        debugLog("insertText \(Self.debugDescription(for: text))")
        super.insertText(text)
    }

    override func deleteBackward() {
        debugLog("deleteBackward")
        super.deleteBackward()
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        .zero
    }

    private func debugLog(_ message: String) {
        guard Self.debugTerminalInput else { return }
        NSLog("SessionKeyboardHostView %@", message)
    }

    private func forwardTextDelta(from oldValue: String, to newValue: String) {
        guard oldValue != newValue, let surface else { return }

        let oldCharacters = Array(oldValue)
        let newCharacters = Array(newValue)

        if newCharacters.starts(with: oldCharacters) {
            let inserted = String(newCharacters.dropFirst(oldCharacters.count))
            if !inserted.isEmpty {
                debugLog("textDelta insert \(Self.debugDescription(for: inserted))")
                surface.insertText(inserted)
            }
            return
        }

        if oldCharacters.starts(with: newCharacters) {
            let deleteCount = oldCharacters.count - newCharacters.count
            debugLog("textDelta delete count=\(deleteCount)")
            for _ in 0..<deleteCount {
                surface.deleteBackward()
            }
            return
        }

        debugLog(
            "textDelta replace old=\(Self.debugDescription(for: oldValue)) new=\(Self.debugDescription(for: newValue))"
        )
        for _ in oldCharacters {
            surface.deleteBackward()
        }
        if !newValue.isEmpty {
            surface.insertText(newValue)
        }
    }

    private static func debugDescription(for string: String) -> String {
        string
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
