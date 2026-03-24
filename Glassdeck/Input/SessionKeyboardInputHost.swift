import SwiftUI
import UIKit

@MainActor
protocol SessionKeyboardInputSink: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
}

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
            inputSink: session.surface,
            isFocused: isFocused,
            softwareKeyboardPresented: softwareKeyboardPresented
        )
    }
}

final class SessionKeyboardHostView: UITextField {
    private static let debugTerminalInput = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private weak var surface: GhosttySurface?
    private weak var inputSink: (any SessionKeyboardInputSink)?
    private let suppressedInputView = UIView(frame: .zero)
    private var softwareKeyboardPresented = false
    private var suppressTextForwarding = false
    private var lastObservedText = ""

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
        addTarget(self, action: #selector(handleEditingChanged), for: .editingChanged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextDidChangeNotification),
            name: UITextField.textDidChangeNotification,
            object: self
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func update(
        surface: GhosttySurface?,
        inputSink: (any SessionKeyboardInputSink)?,
        isFocused: Bool,
        softwareKeyboardPresented: Bool
    ) {
        if self.surface !== surface {
            suppressTextForwarding = true
            text = ""
            suppressTextForwarding = false
            lastObservedText = ""
        }
        self.surface = surface
        self.inputSink = inputSink

        if self.softwareKeyboardPresented != softwareKeyboardPresented {
            self.softwareKeyboardPresented = softwareKeyboardPresented
            inputView = softwareKeyboardPresented ? nil : suppressedInputView
            debugLog("softwareKeyboardPresented=\(softwareKeyboardPresented)")
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
        ensureSoftwareKeyboardPresented()
        if isFirstResponder {
            return true
        }
        return becomeFirstResponder()
    }

    override func insertText(_ text: String) {
        debugLog("insertText \(Self.debugDescription(for: text))")
        if !text.isEmpty {
            inputSink?.insertText(text)
        }
        suppressTextForwarding = true
        super.insertText(text)
        suppressTextForwarding = false
        lastObservedText = self.text ?? ""
    }

    override func deleteBackward() {
        debugLog("deleteBackward")
        inputSink?.deleteBackward()
        suppressTextForwarding = true
        super.deleteBackward()
        suppressTextForwarding = false
        lastObservedText = self.text ?? ""
    }

    override func replace(_ range: UITextRange, withText text: String) {
        debugLog("replace \(Self.debugDescription(for: text))")

        if let replacementRange = replacementRange(for: range, in: self.text ?? "") {
            forwardReplacement(in: replacementRange, with: text, from: self.text ?? "")
        }

        suppressTextForwarding = true
        super.replace(range, withText: text)
        suppressTextForwarding = false
        lastObservedText = self.text ?? ""
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        .zero
    }

    private func ensureSoftwareKeyboardPresented() {
        guard !softwareKeyboardPresented else { return }

        softwareKeyboardPresented = true
        inputView = nil
        debugLog("softwareKeyboardPresented=true")
        reloadInputViews()
        surface?.setSoftwareKeyboardPresented(true)
    }

    @objc
    private func handleEditingChanged() {
        let currentText = text ?? ""
        guard !suppressTextForwarding else {
            lastObservedText = currentText
            return
        }

        forwardTextDelta(from: lastObservedText, to: currentText)
        lastObservedText = currentText
    }

    @objc
    private func handleTextDidChangeNotification(_ notification: Notification) {
        handleEditingChanged()
    }

    private func replacementRange(for textRange: UITextRange, in currentText: String) -> Range<String.Index>? {
        let start = offset(from: beginningOfDocument, to: textRange.start)
        let end = offset(from: beginningOfDocument, to: textRange.end)
        guard start >= 0, end >= start else { return nil }

        let nsRange = NSRange(location: start, length: end - start)
        return Range(nsRange, in: currentText)
    }

    private func forwardReplacement(
        in range: Range<String.Index>,
        with replacementText: String,
        from currentText: String
    ) {
        guard let inputSink else { return }

        let removedCount = currentText[range].count
        if removedCount > 0 {
            debugLog("replace delete count=\(removedCount)")
            for _ in 0..<removedCount {
                inputSink.deleteBackward()
            }
        }

        if !replacementText.isEmpty {
            debugLog("replace insert \(Self.debugDescription(for: replacementText))")
            inputSink.insertText(replacementText)
        }
    }

    private func debugLog(_ message: String) {
        guard Self.debugTerminalInput else { return }
        NSLog("SessionKeyboardHostView %@", message)
    }

    private func forwardTextDelta(from oldValue: String, to newValue: String) {
        guard oldValue != newValue, let inputSink else { return }

        let oldCharacters = Array(oldValue)
        let newCharacters = Array(newValue)

        if newCharacters.starts(with: oldCharacters) {
            let inserted = String(newCharacters.dropFirst(oldCharacters.count))
            if !inserted.isEmpty {
                debugLog("textDelta insert \(Self.debugDescription(for: inserted))")
                inputSink.insertText(inserted)
            }
            return
        }

        if oldCharacters.starts(with: newCharacters) {
            let deleteCount = oldCharacters.count - newCharacters.count
            debugLog("textDelta delete count=\(deleteCount)")
            for _ in 0..<deleteCount {
                inputSink.deleteBackward()
            }
            return
        }

        debugLog(
            "textDelta replace old=\(Self.debugDescription(for: oldValue)) new=\(Self.debugDescription(for: newValue))"
        )
        for _ in oldCharacters {
            inputSink.deleteBackward()
        }
        if !newValue.isEmpty {
            inputSink.insertText(newValue)
        }
    }

    private static func debugDescription(for string: String) -> String {
        string
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
