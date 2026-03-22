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

final class SessionKeyboardHostView: UIView, UITextInput {
    private weak var surface: GhosttySurface?
    private let suppressedInputView = UIView(frame: .zero)
    private var softwareKeyboardPresented = false
    private var _markedText: String?
    private var _markedTextSelectedRange: NSRange = NSRange(location: NSNotFound, length: 0)

    // MARK: - UITextInput token/delegate support

    var inputDelegate: (any UITextInputDelegate)?

    lazy var tokenizer: any UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)

    // MARK: - UITextInput text range support

    private let _beginPosition = SimpleTextPosition(offset: 0)

    var beginningOfDocument: UITextPosition { _beginPosition }
    var endOfDocument: UITextPosition { _beginPosition }

    var selectedTextRange: UITextRange? {
        get { SimpleTextRange(start: _beginPosition, end: _beginPosition) }
        set { }
    }

    var markedTextRange: UITextRange? {
        guard _markedText != nil else { return nil }
        return SimpleTextRange(start: _beginPosition, end: _beginPosition)
    }

    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { nil }
        set { }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityIdentifier = "session-keyboard-host"
        accessibilityLabel = "Software Keyboard Host"
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

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            surface?.setFocused(true)
        }
        return result
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            surface?.setFocused(false)
        }
        return result
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

        accessibilityValue = softwareKeyboardPresented ? "presented" : "hidden"

        if isFocused {
            if !isFirstResponder {
                becomeFirstResponder()
            }
        } else if isFirstResponder {
            resignFirstResponder()
        }
    }

    func insertText(_ text: String) {
        _markedText = nil
        surface?.insertText(text)
    }

    func deleteBackward() {
        if _markedText != nil {
            _markedText = nil
            surface?.setMarkedText(nil)
            return
        }
        surface?.deleteBackward()
    }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        _markedText = markedText
        _markedTextSelectedRange = selectedRange
        surface?.setMarkedText(markedText)
    }

    func unmarkText() {
        _markedText = nil
        surface?.unmarkText()
    }

    func text(in range: UITextRange) -> String? { "" }

    func replace(_ range: UITextRange, withText text: String) {
        insertText(text)
    }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        SimpleTextRange(start: _beginPosition, end: _beginPosition)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        _beginPosition
    }

    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        _beginPosition
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        .orderedSame
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        0
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        _beginPosition
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        SimpleTextRange(start: _beginPosition, end: _beginPosition)
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    func firstRect(for range: UITextRange) -> CGRect {
        guard let surface else { return .zero }
        let surfaceRect = surface.cursorRectForIME()
        return surface.convert(surfaceRect, to: self)
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        guard let surface else { return .zero }
        let surfaceRect = surface.cursorRectForIME()
        return surface.convert(surfaceRect, to: self)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        _beginPosition
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        _beginPosition
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        nil
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

/// A trivial `UITextPosition` subclass used by `SessionKeyboardHostView`.
private final class SimpleTextPosition: UITextPosition {
    let offset: Int
    init(offset: Int) { self.offset = offset }
}

/// A trivial `UITextRange` subclass used by `SessionKeyboardHostView`.
private final class SimpleTextRange: UITextRange {
    private let _start: SimpleTextPosition
    private let _end: SimpleTextPosition
    override var start: UITextPosition { _start }
    override var end: UITextPosition { _end }
    override var isEmpty: Bool { _start.offset == _end.offset }
    init(start: SimpleTextPosition, end: SimpleTextPosition) {
        _start = start
        _end = end
    }
}
#endif
