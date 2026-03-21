#if canImport(UIKit)
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

final class SessionKeyboardHostView: UIView, UIKeyInput {
    private weak var surface: GhosttySurface?
    private let suppressedInputView = UIView(frame: .zero)
    private var softwareKeyboardPresented = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityIdentifier = "session-keyboard-host"
        accessibilityTraits.insert(.allowsDirectInteraction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var canResignFirstResponder: Bool {
        true
    }

    override var inputView: UIView? {
        softwareKeyboardPresented ? nil : suppressedInputView
    }

    var hasText: Bool {
        true
    }

    func update(surface: GhosttySurface?, isFocused: Bool, softwareKeyboardPresented: Bool) {
        self.surface = surface

        if self.softwareKeyboardPresented != softwareKeyboardPresented {
            self.softwareKeyboardPresented = softwareKeyboardPresented
            reloadInputViews()
        }

        if isFocused {
            if !isFirstResponder {
                becomeFirstResponder()
            }
        } else if isFirstResponder {
            resignFirstResponder()
        }
    }

    func insertText(_ text: String) {
        surface?.insertText(text)
    }

    func deleteBackward() {
        surface?.deleteBackward()
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
}
#endif
