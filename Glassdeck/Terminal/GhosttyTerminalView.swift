#if canImport(UIKit)
import AudioToolbox
import CoreImage
import Foundation
import GlassdeckCore
import Metal
import SwiftUI
import UIKit

struct GhosttySurfaceState: Sendable, Equatable {
    let title: String?
    let terminalSize: TerminalSize
    let pixelSize: TerminalPixelSize?
    let scrollbackLines: Int
    let isHealthy: Bool
    let renderFailureReason: String?
    let visibleTextSummary: String
    let hasRenderedFrame: Bool
    let animationProgress: GhosttyHomeAnimationProgress?
    let interactionGeometry: RemoteTerminalGeometry
    let interactionCapabilities: GhosttyVTInteractionCapabilities
    let softwareKeyboardPresented: Bool
}

struct GhosttySurfaceMetricsPreset: Equatable {
    let cellSize: CGSize
    let padding: UIEdgeInsets
    let accentForegroundColor: GhosttyVTColor?
}

enum GhosttySurfaceDisplayMode: Sendable, Equatable {
    case standard
    case externalDisplay
}

enum GhosttySurfaceLayoutMetrics {
    @MainActor
    static func displayMode(for windowScene: UIWindowScene?) -> GhosttySurfaceDisplayMode {
        guard windowScene?.session.role == .windowExternalDisplayNonInteractive else {
            return .standard
        }
        return .externalDisplay
    }

    static func fontSize(for configuration: TerminalConfiguration, mode: GhosttySurfaceDisplayMode) -> CGFloat {
        CGFloat(configuration.fontSize)
    }

    static func cellSize(
        for configuration: TerminalConfiguration,
        mode: GhosttySurfaceDisplayMode,
        metricsPreset: GhosttySurfaceMetricsPreset?
    ) -> CGSize {
        if let metricsPreset {
            return metricsPreset.cellSize
        }

        let font = UIFont.monospacedSystemFont(
            ofSize: fontSize(for: configuration, mode: mode),
            weight: .regular
        )
        let characterSize = ("W" as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: max(8, ceil(characterSize.width)),
            height: max(12, ceil(font.lineHeight * 1.15))
        )
    }

    static func basePadding(
        for bounds: CGRect,
        mode: GhosttySurfaceDisplayMode,
        metricsPreset: GhosttySurfaceMetricsPreset?
    ) -> UIEdgeInsets {
        if let metricsPreset {
            return metricsPreset.padding
        }

        let horizontalInset: CGFloat
        let verticalInset: CGFloat
        switch mode {
        case .standard:
            horizontalInset = max(8, floor(bounds.width * 0.015))
            verticalInset = max(8, floor(bounds.height * 0.02))
        case .externalDisplay:
            horizontalInset = max(12, floor(bounds.width * 0.02))
            verticalInset = max(12, floor(bounds.height * 0.025))
        }

        return UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    static func textRect(
        for cellRect: CGRect,
        font: UIFont
    ) -> CGRect {
        cellRect.insetBy(
            dx: 0,
            dy: max(0, floor((cellRect.height - font.lineHeight) / 2))
        )
    }
}

@MainActor
final class GhosttySurface: UIView, UIKeyInput {
    private static let cursorBlinkInterval: TimeInterval = 0.6
    private static let bellSoundID: SystemSoundID = 1103

    private let configuration: TerminalConfiguration
    private let engine: GhosttyVTTerminalEngine
    private let renderer: GhosttyMetalRenderer
    private let softwareMirrorView = UIImageView()

    private var outputHandler: (@Sendable (Data) -> Void)?
    private var currentTerminalSize = TerminalSize(columns: 80, rows: 24)
    private var currentPixelSize = TerminalPixelSize(width: 0, height: 0)
    private var currentMetrics = GhosttyMetalRenderer.Metrics.zero
    private var terminalIsFocused = false
    private var lastScrollRows = 0
    private var currentScrollbackLines = 0
    private var currentRenderFailureReason: String?
    private var currentVisibleTextSummary = ""
    private var currentHasRenderedFrame = false
    private var latestProjectionForState: GhosttyVTRenderProjection?
    private var currentAnimationProgress: GhosttyHomeAnimationProgress?
    private var currentAnimationAccentColumnsByRow: [Int: IndexSet]?
    private var cursorBlinkTimer: Timer?
    private var cursorBlinkPhaseVisible = true
    private var currentSoftwareKeyboardPresented = false
    private var currentInteractionCapabilities = GhosttyVTInteractionCapabilities(
        supportsMousePlacement: false,
        supportsScrollReporting: false
    )

    var title: String?
    var isHealthy = true
    var cellSize: CGSize = .zero
    var onResize: ((Int, Int, TerminalPixelSize) -> Void)?
    var onStateChange: ((GhosttySurfaceState) -> Void)?
    var onSoftwareKeyboardPresentationChange: ((Bool) -> Void)?
    var hasSoftwareMirrorImage: Bool {
        softwareMirrorView.image != nil
    }
    var terminalConfiguration: TerminalConfiguration {
        configuration
    }

    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    private static var usesSoftwareMirrorPresentation: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    var terminalSize: TerminalSize {
        currentTerminalSize
    }

    var pixelSize: TerminalPixelSize? {
        currentPixelSize.width > 0 && currentPixelSize.height > 0 ? currentPixelSize : nil
    }

    var stateSnapshot: GhosttySurfaceState {
        let visibleTextSummary: String
        if currentVisibleTextSummary.isEmpty, let latestProjectionForState {
            visibleTextSummary = Self.visibleTextSummary(from: latestProjectionForState)
        } else {
            visibleTextSummary = currentVisibleTextSummary
        }

        return GhosttySurfaceState(
            title: title,
            terminalSize: currentTerminalSize,
            pixelSize: pixelSize,
            scrollbackLines: currentScrollbackLines,
            isHealthy: isHealthy,
            renderFailureReason: currentRenderFailureReason,
            visibleTextSummary: visibleTextSummary,
            hasRenderedFrame: currentHasRenderedFrame,
            animationProgress: currentAnimationProgress,
            interactionGeometry: interactionGeometry,
            interactionCapabilities: currentInteractionCapabilities,
            softwareKeyboardPresented: currentSoftwareKeyboardPresented
        )
    }

    static func previewBounds(
        for terminalSize: TerminalSize,
        configuration: TerminalConfiguration = TerminalConfiguration(),
        metricsPreset: GhosttySurfaceMetricsPreset? = nil
    ) -> CGRect {
        GhosttyMetalRenderer.previewBounds(
            for: terminalSize,
            configuration: configuration,
            metricsPreset: metricsPreset
        )
    }

    var interactionGeometry: RemoteTerminalGeometry {
        RemoteTerminalGeometry(
            terminalSize: currentMetrics.terminalSize,
            surfacePixelSize: currentMetrics.pixelSize,
            cellPixelSize: currentMetrics.cellPixelSize,
            padding: RemoteControlInsets(
                top: Int((currentMetrics.padding.top * currentMetrics.displayScale).rounded()),
                left: Int((currentMetrics.padding.left * currentMetrics.displayScale).rounded()),
                bottom: Int((currentMetrics.padding.bottom * currentMetrics.displayScale).rounded()),
                right: Int((currentMetrics.padding.right * currentMetrics.displayScale).rounded())
            ),
            displayScale: currentMetrics.displayScale
        )
    }

    init(
        configuration: TerminalConfiguration = TerminalConfiguration(),
        metricsPreset: GhosttySurfaceMetricsPreset? = nil
    ) throws {
        self.configuration = configuration
        self.engine = try GhosttyVTTerminalEngine(
            options: GhosttyVTTerminalOptions(
                columns: 80,
                rows: 24,
                scrollbackLines: configuration.scrollbackLines
            )
        )
        self.renderer = try GhosttyMetalRenderer(
            configuration: configuration,
            metricsPreset: metricsPreset
        )
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var canBecomeFirstResponder: Bool { false }

    override var canResignFirstResponder: Bool { false }

    var hasText: Bool {
        true
    }

    func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) {
        outputHandler = handler
    }

    func writeToTerminal(_ data: Data) {
        if configuration.bellSound, data.contains(0x07) {
            AudioServicesPlaySystemSound(Self.bellSoundID)
        }
        engine.write(data)
        render(clearDirty: true)
    }

    func setAnimationAccentRows(_ accentColumnsByRow: [Int: IndexSet]?) {
        currentAnimationAccentColumnsByRow = accentColumnsByRow
    }

    func setAnimationProgress(_ progress: GhosttyHomeAnimationProgress?) {
        guard currentAnimationProgress != progress else { return }
        currentAnimationProgress = progress
        publishState()
    }

    func setSoftwareKeyboardPresented(_ presented: Bool) {
        guard currentSoftwareKeyboardPresented != presented else { return }
        currentSoftwareKeyboardPresented = presented
        onSoftwareKeyboardPresentationChange?(presented)
        publishState()
    }

    func setFocused(_ focused: Bool) {
        guard focused != terminalIsFocused else { return }
        terminalIsFocused = focused

        if let data = try? engine.encodeFocus(focused), !data.isEmpty {
            outputHandler?(data)
        }
        updateCursorBlinkTimer()
        render(clearDirty: true)
        publishState()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            terminalIsFocused = true
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            terminalIsFocused = false
        }
        return result
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            updateLayout()
        }
        updateCursorBlinkTimer()
    }

    func insertText(_ text: String) {
        let event = GhosttyVTKeyEventDescriptor(text: text)
        sendKey(event)
    }

    func deleteBackward() {
        sendKey(
            GhosttyVTKeyEventDescriptor(
                keyCode: .backspace
            )
        )
    }

    override func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string else { return }
        guard let data = try? engine.encodePaste(Data(string.utf8)) else { return }
        outputHandler?(data)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = handleHardwarePresses(presses, action: .press)
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = handleHardwarePresses(presses, action: .release)
        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = handleHardwarePresses(presses, action: .release)
        if !unhandled.isEmpty {
            super.pressesCancelled(unhandled, with: event)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        setFocused(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    private func setupView() {
        backgroundColor = Self.color(for: configuration.colorScheme.theme.background)
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityIdentifier = "ghostty-terminal-surface"
        accessibilityTraits.insert(.allowsDirectInteraction)
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = traitCollection.displayScale

        softwareMirrorView.backgroundColor = .clear
        softwareMirrorView.contentMode = .scaleToFill
        softwareMirrorView.isUserInteractionEnabled = false
        softwareMirrorView.frame = bounds
        softwareMirrorView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        softwareMirrorView.isHidden = !Self.usesSoftwareMirrorPresentation
        addSubview(softwareMirrorView)

        let scrollRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        scrollRecognizer.minimumNumberOfTouches = 2
        scrollRecognizer.maximumNumberOfTouches = 2
        addGestureRecognizer(scrollRecognizer)

        if #available(iOS 13.4, *) {
            let hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            addGestureRecognizer(hoverRecognizer)
        }
    }

    @objc private func handleScrollPan(_ recognizer: UIPanGestureRecognizer) {
        guard currentMetrics.cellSize.height > 0 else { return }
        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            recognizer.setTranslation(.zero, in: self)
            lastScrollRows = 0
            return
        }

        let translation = recognizer.translation(in: self)
        let rowDelta = Int(translation.y / currentMetrics.cellSize.height)
        guard rowDelta != lastScrollRows else { return }

        engine.scrollViewport(delta: rowDelta - lastScrollRows)
        lastScrollRows = rowDelta
        render(clearDirty: true)
    }

    @available(iOS 13.4, *)
    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        let location = recognizer.location(in: self)
        guard let descriptor = mouseDescriptor(
            action: .motion,
            button: nil,
            location: location
        ) else {
            return
        }
        if let data = try? engine.encodeMouse(descriptor), !data.isEmpty {
            outputHandler?(data)
        }
    }

    private func updateLayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = traitCollection.displayScale
        let displayMode = GhosttySurfaceLayoutMetrics.displayMode(for: window?.windowScene)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        let previousTerminalSize = currentTerminalSize
        let previousPixelSize = currentPixelSize
        let metrics = renderer.metrics(for: bounds, scale: scale, displayMode: displayMode)
        currentMetrics = metrics
        cellSize = metrics.cellSize

        guard metrics.terminalSize != previousTerminalSize || metrics.pixelSize != previousPixelSize else {
            render(clearDirty: true)
            return
        }

        currentTerminalSize = metrics.terminalSize
        currentPixelSize = metrics.pixelSize

        do {
            try engine.resize(
                columns: numericCast(metrics.terminalSize.columns),
                rows: numericCast(metrics.terminalSize.rows)
            )
            if let sizeReport = try engine.encodeInBandResizeReport(
                pixelSize: metrics.pixelSize,
                cellPixelSize: metrics.cellPixelSize
            ), !sizeReport.isEmpty {
                outputHandler?(sizeReport)
            }
        } catch {
            isHealthy = false
            publishState()
        }

        onResize?(
            metrics.terminalSize.columns,
            metrics.terminalSize.rows,
            metrics.pixelSize
        )
        render(clearDirty: true)
    }

    private func render(clearDirty: Bool) {
        do {
            let projection = try engine.snapshotProjection(clearDirty: clearDirty)
            latestProjectionForState = projection
            currentInteractionCapabilities = try engine.interactionCapabilities()
            currentScrollbackLines = max(0, Int((projection.scrollbar?.total ?? 0)) - projection.rows)
            if onStateChange != nil {
                currentVisibleTextSummary = Self.visibleTextSummary(from: projection)
            } else {
                currentVisibleTextSummary = ""
            }
            renderer.render(
                projection: projection,
                in: metalLayer,
                bounds: bounds,
                metrics: currentMetrics,
                focused: terminalIsFocused,
                cursorBlinkPhaseVisible: cursorBlinkPhaseVisible,
                accentColumnsByRow: currentAnimationAccentColumnsByRow
            )
            if Self.usesSoftwareMirrorPresentation {
                softwareMirrorView.image = renderer.cachedFrameImage
            }
            isHealthy = true
            currentHasRenderedFrame = currentMetrics.pixelSize.width > 0
                && currentMetrics.pixelSize.height > 0
            currentRenderFailureReason = nil
            updateCursorBlinkTimer()
        } catch {
            isHealthy = false
            if Self.usesSoftwareMirrorPresentation {
                softwareMirrorView.image = nil
            }
            currentRenderFailureReason = Self.renderFailureReason(from: error)
            updateCursorBlinkTimer()
        }
        publishState()
    }

    private func updateCursorBlinkTimer() {
        let shouldBlink =
            configuration.cursorBlink
            && terminalIsFocused
            && window != nil
            && latestProjectionForState?.cursor.visible == true

        guard shouldBlink else {
            cursorBlinkTimer?.invalidate()
            cursorBlinkTimer = nil
            cursorBlinkPhaseVisible = true
            return
        }

        guard cursorBlinkTimer == nil else { return }
        cursorBlinkPhaseVisible = true
        let timer = Timer(
            timeInterval: Self.cursorBlinkInterval,
            target: self,
            selector: #selector(handleCursorBlinkTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        cursorBlinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func handleCursorBlinkTimer(_ timer: Timer) {
        cursorBlinkPhaseVisible.toggle()
        render(clearDirty: false)
    }

    private func publishState() {
        onStateChange?(stateSnapshot)
    }

    private static func visibleTextSummary(from projection: GhosttyVTRenderProjection) -> String {
        projection.rowsProjection
            .sorted { $0.index < $1.index }
            .map(Self.visibleTextRow(from:))
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func visibleTextRow(from row: GhosttyVTRowProjection) -> String {
        let text = row.cells
            .sorted { $0.column < $1.column }
            .compactMap { cell -> String? in
                switch cell.width {
                case .spacerHead, .spacerTail:
                    return nil
                case .narrow, .wide:
                    return cell.text.isEmpty ? " " : cell.text
                }
            }
            .joined()

        return text.replacingOccurrences(
            of: #"\s+$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func renderFailureReason(from error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            return description
        }
        return String(describing: error)
    }

    private static func color(for color: GhosttyVTColor) -> UIColor {
        UIColor(
            red: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }

    func sendRemoteMouse(
        action: GhosttyVTMouseAction,
        button: GhosttyVTMouseButton?,
        surfacePixelPoint: CGPoint
    ) -> Bool {
        guard let descriptor = mouseDescriptor(
            action: action,
            button: button,
            surfacePixelPoint: interactionGeometry.clampedSurfacePixelPoint(surfacePixelPoint)
        ) else {
            return false
        }

        do {
            guard let data = try engine.encodeMouse(descriptor), !data.isEmpty else { return false }
            outputHandler?(data)
            return true
        } catch {
            isHealthy = false
            publishState()
            return false
        }
    }

    func sendRemoteScroll(steps: Int, surfacePixelPoint: CGPoint) -> Bool {
        guard steps != 0 else { return false }
        guard currentInteractionCapabilities.supportsScrollReporting else { return false }
        guard let coordinates = sgrScrollCoordinates(for: surfacePixelPoint) else { return false }

        let button = steps > 0 ? 65 : 64
        for _ in 0..<abs(steps) {
            let sequence = "\u{1B}[<\(button);\(coordinates.column);\(coordinates.row)M"
            outputHandler?(Data(sequence.utf8))
        }
        return true
    }

    @discardableResult
    func handleHardwarePresses(
        _ presses: Set<UIPress>,
        action: GhosttyVTKeyAction
    ) -> Set<UIPress> {
        var unhandled = Set<UIPress>()

        for press in presses {
            guard
                let key = press.key,
                let descriptor = keyDescriptor(for: key, action: action)
            else {
                unhandled.insert(press)
                continue
            }

            if shouldUseTextInputFallback(descriptor: descriptor, action: action) {
                unhandled.insert(press)
                continue
            }

            sendKey(descriptor)
        }

        return unhandled
    }

    private func sendKey(_ descriptor: GhosttyVTKeyEventDescriptor) {
        do {
            guard let data = try engine.encodeKey(descriptor), !data.isEmpty else { return }
            outputHandler?(data)
        } catch {
            isHealthy = false
        }
    }

    private func handleTouchMouse(
        _ touches: Set<UITouch>,
        action: GhosttyVTMouseAction,
        button: GhosttyVTMouseButton?
    ) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        _ = sendRemoteMouse(
            action: action,
            button: button,
            surfacePixelPoint: CGPoint(
                x: location.x * traitCollection.displayScale,
                y: location.y * traitCollection.displayScale
            )
        )
    }

    private func mouseDescriptor(
        action: GhosttyVTMouseAction,
        button: GhosttyVTMouseButton?,
        location: CGPoint
    ) -> GhosttyVTMouseEventDescriptor? {
        mouseDescriptor(
            action: action,
            button: button,
            surfacePixelPoint: CGPoint(
                x: location.x * traitCollection.displayScale,
                y: location.y * traitCollection.displayScale
            )
        )
    }

    private func mouseDescriptor(
        action: GhosttyVTMouseAction,
        button: GhosttyVTMouseButton?,
        surfacePixelPoint: CGPoint
    ) -> GhosttyVTMouseEventDescriptor? {
        guard currentMetrics.pixelSize.width > 0, currentMetrics.pixelSize.height > 0 else {
            return nil
        }

        return GhosttyVTMouseEventDescriptor(
            action: action,
            button: button,
            modifiers: [],
            position: GhosttyVTPoint(
                x: surfacePixelPoint.x,
                y: surfacePixelPoint.y
            ),
            sizeContext: currentMetrics.mouseSizeContext
        )
    }

    private func sgrScrollCoordinates(for surfacePixelPoint: CGPoint) -> (column: Int, row: Int)? {
        guard let cell = interactionGeometry.cellPosition(forSurfacePixelPoint: surfacePixelPoint) else {
            return nil
        }
        return (cell.column + 1, cell.row + 1)
    }

    private func keyDescriptor(
        for key: UIKey,
        action: GhosttyVTKeyAction
    ) -> GhosttyVTKeyEventDescriptor? {
        let text = action == .release ? "" : key.characters
        let keyCode = key.keyCode.ghosttyKeyCode
        if keyCode == nil && text.isEmpty {
            return nil
        }

        return GhosttyVTKeyEventDescriptor(
            action: action,
            keyCode: keyCode,
            modifiers: GhosttyVTModifiers(key.modifierFlags),
            text: text,
            unshiftedText: key.charactersIgnoringModifiers.nilIfEmpty
        )
    }

    private func shouldUseTextInputFallback(
        descriptor: GhosttyVTKeyEventDescriptor,
        action: GhosttyVTKeyAction
    ) -> Bool {
        guard action == .press else { return false }
        guard descriptor.modifiers.isEmpty else { return false }
        guard let keyCode = descriptor.keyCode else { return false }

        switch keyCode {
        case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
             .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
             .digit0, .digit1, .digit2, .digit3, .digit4, .digit5,
             .digit6, .digit7, .digit8, .digit9, .space, .tab,
             .comma, .period, .slash, .backquote, .minus, .equal,
             .quote, .semicolon, .backslash, .bracketLeft, .bracketRight:
            return !descriptor.text.isEmpty
        default:
            return false
        }
    }
}

final class GhosttySurfaceTerminalIO: TerminalIO, @unchecked Sendable {
    private weak var surface: GhosttySurface?

    init(surface: GhosttySurface) {
        self.surface = surface
    }

    func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) async {
        await MainActor.run {
            surface?.setOutputHandler(handler)
        }
    }

    func write(_ data: Data) async {
        await MainActor.run {
            surface?.writeToTerminal(data)
        }
    }
}

private final class GhosttyMetalRenderer {
    struct Metrics: Sendable, Equatable {
        var terminalSize: TerminalSize
        var pixelSize: TerminalPixelSize
        var cellSize: CGSize
        var cellPixelSize: TerminalPixelSize
        var padding: UIEdgeInsets
        var displayScale: CGFloat
        var displayMode: GhosttySurfaceDisplayMode

        static let zero = Metrics(
            terminalSize: TerminalSize(columns: 80, rows: 24),
            pixelSize: TerminalPixelSize(width: 0, height: 0),
            cellSize: .zero,
            cellPixelSize: TerminalPixelSize(width: 0, height: 0),
            padding: .zero,
            displayScale: 1,
            displayMode: .standard
        )

        var mouseSizeContext: GhosttyVTMouseSizeContext {
            GhosttyVTMouseSizeContext(
                screenWidth: pixelSize.width,
                screenHeight: pixelSize.height,
                cellWidth: cellPixelSize.width,
                cellHeight: cellPixelSize.height,
                paddingTop: Int((padding.top * displayScale).rounded()),
                paddingBottom: Int((padding.bottom * displayScale).rounded()),
                paddingRight: Int((padding.right * displayScale).rounded()),
                paddingLeft: Int((padding.left * displayScale).rounded())
            )
        }
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let configuration: TerminalConfiguration
    private let metricsPreset: GhosttySurfaceMetricsPreset?

    private var cachedFrame: UIImage?

    var cachedFrameImage: UIImage? {
        cachedFrame
    }

    init(
        configuration: TerminalConfiguration,
        metricsPreset: GhosttySurfaceMetricsPreset? = nil
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw GhosttyVTError.unavailable
        }

        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device)
        self.configuration = configuration
        self.metricsPreset = metricsPreset
    }

    func metrics(
        for bounds: CGRect,
        scale: CGFloat,
        displayMode: GhosttySurfaceDisplayMode = .standard
    ) -> Metrics {
        Self.metrics(
            for: bounds,
            scale: scale,
            displayMode: displayMode,
            configuration: configuration,
            metricsPreset: metricsPreset
        )
    }

    static func previewBounds(
        for terminalSize: TerminalSize,
        configuration: TerminalConfiguration,
        metricsPreset: GhosttySurfaceMetricsPreset? = nil
    ) -> CGRect {
        let cellSize = GhosttySurfaceLayoutMetrics.cellSize(
            for: configuration,
            mode: .standard,
            metricsPreset: metricsPreset
        )

        let width: CGFloat
        let height: CGFloat
        if let metricsPreset {
            width = ceil(
                CGFloat(terminalSize.columns) * cellSize.width
                + metricsPreset.padding.left
                + metricsPreset.padding.right
            )
            height = ceil(
                CGFloat(terminalSize.rows) * cellSize.height
                + metricsPreset.padding.top
                + metricsPreset.padding.bottom
            )
        } else {
            width = Self.dimension(
                for: terminalSize.columns,
                cellExtent: cellSize.width,
                insetFraction: 0.015
            )
            height = Self.dimension(
                for: terminalSize.rows,
                cellExtent: cellSize.height,
                insetFraction: 0.02
            )
        }

        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private static func metrics(
        for bounds: CGRect,
        scale: CGFloat,
        displayMode: GhosttySurfaceDisplayMode,
        configuration: TerminalConfiguration,
        metricsPreset: GhosttySurfaceMetricsPreset?
    ) -> Metrics {
        let cellSize = GhosttySurfaceLayoutMetrics.cellSize(
            for: configuration,
            mode: displayMode,
            metricsPreset: metricsPreset
        )
        let basePadding = GhosttySurfaceLayoutMetrics.basePadding(
            for: bounds,
            mode: displayMode,
            metricsPreset: metricsPreset
        )
        let usableWidth = max(1, bounds.width - basePadding.left - basePadding.right)
        let usableHeight = max(1, bounds.height - basePadding.top - basePadding.bottom)

        let columns = max(2, Int(usableWidth / cellSize.width))
        let rows = max(2, Int(usableHeight / cellSize.height))

        let contentWidth = CGFloat(columns) * cellSize.width
        let contentHeight = CGFloat(rows) * cellSize.height
        let extraHorizontal = max(0, bounds.width - basePadding.left - basePadding.right - contentWidth)
        let extraVertical = max(0, bounds.height - basePadding.top - basePadding.bottom - contentHeight)
        let padding = UIEdgeInsets(
            top: basePadding.top + floor(extraVertical / 2),
            left: basePadding.left + floor(extraHorizontal / 2),
            bottom: basePadding.bottom + ceil(extraVertical / 2),
            right: basePadding.right + ceil(extraHorizontal / 2)
        )

        return Metrics(
            terminalSize: TerminalSize(columns: columns, rows: rows),
            pixelSize: TerminalPixelSize(
                width: Int((bounds.width * scale).rounded()),
                height: Int((bounds.height * scale).rounded())
            ),
            cellSize: cellSize,
            cellPixelSize: TerminalPixelSize(
                width: max(1, Int((cellSize.width * scale).rounded())),
                height: max(1, Int((cellSize.height * scale).rounded()))
            ),
            padding: padding,
            displayScale: scale,
            displayMode: displayMode
        )
    }

    private static func dimension(
        for cellCount: Int,
        cellExtent: CGFloat,
        insetFraction: CGFloat
    ) -> CGFloat {
        let minimumDimension = CGFloat(cellCount) * cellExtent
        var dimension = ceil(minimumDimension)

        while dimension < minimumDimension + 512 {
            let inset = max(8, floor(dimension * insetFraction))
            let resolvedCount = Int(max(1, dimension - (inset * 2)) / cellExtent)
            if resolvedCount == cellCount {
                return dimension
            }
            dimension += 1
        }

        return ceil(minimumDimension + 64)
    }

    func render(
        projection: GhosttyVTRenderProjection,
        in layer: CAMetalLayer,
        bounds: CGRect,
        metrics: Metrics,
        focused: Bool,
        cursorBlinkPhaseVisible: Bool,
        accentColumnsByRow: [Int: IndexSet]?
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        #if targetEnvironment(simulator)
        let drawable: CAMetalDrawable? = nil
        #else
        guard let drawable = layer.nextDrawable() else { return }
        #endif

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = layer.contentsScale
        format.opaque = true
        let imageRenderer = UIGraphicsImageRenderer(size: bounds.size, format: format)

        let projection = themedProjection(from: projection)
        let shouldReuseFrame = projection.dirtyState == .partial && cachedFrame != nil
        let dirtyRows = Set(projection.dirtyRows)

        let accentForegroundColor = metricsPreset?.accentForegroundColor.map(color(for:))
        let image = imageRenderer.image { context in
            if shouldReuseFrame, let cachedFrame {
                cachedFrame.draw(in: bounds)
            } else {
                color(for: projection.backgroundColor).setFill()
                context.fill(bounds)
            }

            let rowsToDraw: [GhosttyVTRowProjection]
            if shouldReuseFrame, !dirtyRows.isEmpty {
                rowsToDraw = projection.rowsProjection.filter { dirtyRows.contains($0.index) }
            } else {
                rowsToDraw = projection.rowsProjection
            }

            for row in rowsToDraw {
                draw(
                    row: row,
                    projection: projection,
                    metrics: metrics,
                    fillsDefaultBackground: shouldReuseFrame,
                    accentColumns: accentColumnsByRow?[row.index],
                    accentForegroundColor: accentForegroundColor
                )
            }

            drawCursor(
                projection: projection,
                metrics: metrics,
                focused: focused,
                cursorBlinkPhaseVisible: cursorBlinkPhaseVisible
            )
        }

        cachedFrame = image

        #if !targetEnvironment(simulator)
        guard let cgImage = image.cgImage else { return }

        let ciImage = CIImage(cgImage: cgImage)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let renderBounds = CGRect(origin: .zero, size: layer.drawableSize)
        ciContext.render(
            ciImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: renderBounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
        #endif
    }

    private func regularFont(for metrics: Metrics) -> UIFont {
        UIFont.monospacedSystemFont(
            ofSize: GhosttySurfaceLayoutMetrics.fontSize(for: configuration, mode: metrics.displayMode),
            weight: .regular
        )
    }

    private func boldFont(for metrics: Metrics) -> UIFont {
        UIFont.monospacedSystemFont(
            ofSize: GhosttySurfaceLayoutMetrics.fontSize(for: configuration, mode: metrics.displayMode),
            weight: .bold
        )
    }

    private func draw(
        row: GhosttyVTRowProjection,
        projection: GhosttyVTRenderProjection,
        metrics: Metrics,
        fillsDefaultBackground: Bool,
        accentColumns: IndexSet?,
        accentForegroundColor: UIColor?
    ) {
        let defaultBackground = color(for: projection.backgroundColor)
        let resolvedRegularFont = regularFont(for: metrics)
        let resolvedBoldFont = boldFont(for: metrics)
        if drawAttributedNarrowRowIfPossible(
            row: row,
            projection: projection,
            metrics: metrics,
            fillsDefaultBackground: fillsDefaultBackground,
            accentColumns: accentColumns,
            regularFont: resolvedRegularFont,
            boldFont: resolvedBoldFont
        ) {
            return
        }

        var runStartColumn: Int?
        var runText = ""
        var runWidth = 0
        var runStyle: GhosttyVTTextStyle?
        var runUsesAccent = false

        func flushRun() {
            guard
                let startColumn = runStartColumn,
                let style = runStyle
            else {
                return
            }

            drawTextRun(
                text: runText,
                style: style,
                startColumn: startColumn,
                width: runWidth,
                rowIndex: row.index,
                projection: projection,
                metrics: metrics,
                fillsDefaultBackground: fillsDefaultBackground,
                defaultBackground: defaultBackground,
                accentForegroundColor: runUsesAccent ? accentForegroundColor : nil,
                regularFont: resolvedRegularFont,
                boldFont: resolvedBoldFont
            )

            runStartColumn = nil
            runText = ""
            runWidth = 0
            runStyle = nil
            runUsesAccent = false
        }

        for cell in row.cells {
            let cellUsesAccent = accentColumns?.contains(cell.column) == true
            switch cell.width {
            case .spacerHead, .spacerTail:
                flushRun()
                continue
            case .wide:
                flushRun()
                drawCell(
                    cell,
                    rowIndex: row.index,
                    projection: projection,
                    metrics: metrics,
                    fillsDefaultBackground: fillsDefaultBackground,
                    defaultBackground: defaultBackground,
                    accentForegroundColor: cellUsesAccent ? accentForegroundColor : nil,
                    regularFont: resolvedRegularFont,
                    boldFont: resolvedBoldFont
                )
            case .narrow:
                if runStartColumn == nil {
                    runStartColumn = cell.column
                    runStyle = cell.style
                    runUsesAccent = cellUsesAccent
                } else if runStyle != cell.style || runUsesAccent != cellUsesAccent {
                    flushRun()
                    runStartColumn = cell.column
                    runStyle = cell.style
                    runUsesAccent = cellUsesAccent
                }

                runWidth += 1
                runText.append(cell.text.isEmpty ? " " : cell.text)
            }
        }

        flushRun()
    }

    private func drawAttributedNarrowRowIfPossible(
        row: GhosttyVTRowProjection,
        projection: GhosttyVTRenderProjection,
        metrics: Metrics,
        fillsDefaultBackground: Bool,
        accentColumns: IndexSet?,
        regularFont: UIFont,
        boldFont: UIFont
    ) -> Bool {
        guard !fillsDefaultBackground else { return false }
        guard accentColumns?.isEmpty != false else { return false }

        let cells = row.cells.sorted { $0.column < $1.column }
        guard cells.allSatisfy({ $0.width == .narrow }) else { return false }
        guard cells.allSatisfy({ styleUsesDefaultBackground($0.style) }) else { return false }

        let lineRect = cellRect(
            column: 0,
            row: row.index,
            width: cells.count,
            metrics: metrics
        )
        let drawPoint = CGPoint(
            x: lineRect.minX,
            y: lineRect.minY + max(0, floor((lineRect.height - regularFont.lineHeight) / 2))
        )

        let attributed = NSMutableAttributedString()
        var runStyle: GhosttyVTTextStyle?
        var runText = ""

        func flushRun() {
            guard let style = runStyle, !runText.isEmpty else {
                runText = ""
                return
            }

            let colors = resolvedColors(for: style, projection: projection)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: style.bold ? boldFont : regularFont,
                .foregroundColor: colors.foreground.withAlphaComponent(style.faint ? 0.6 : 1.0),
                .underlineStyle: style.underline == 0 ? 0 : NSUnderlineStyle.single.rawValue,
                .strikethroughStyle: style.strikethrough ? NSUnderlineStyle.single.rawValue : 0
            ]
            attributed.append(NSAttributedString(string: runText, attributes: attributes))
            runText = ""
        }

        for cell in cells {
            if runStyle == nil {
                runStyle = cell.style
            } else if runStyle != cell.style {
                flushRun()
                runStyle = cell.style
            }

            runText.append(cell.text.isEmpty ? " " : cell.text)
        }

        flushRun()
        guard attributed.length > 0 else { return false }

        attributed.draw(at: drawPoint)
        return true
    }

    private func styleUsesDefaultBackground(_ style: GhosttyVTTextStyle) -> Bool {
        style.background == .none && !style.inverse
    }

    private func drawTextRun(
        text: String,
        style: GhosttyVTTextStyle,
        startColumn: Int,
        width: Int,
        rowIndex: Int,
        projection: GhosttyVTRenderProjection,
        metrics: Metrics,
        fillsDefaultBackground: Bool,
        defaultBackground: UIColor,
        accentForegroundColor: UIColor?,
        regularFont: UIFont,
        boldFont: UIFont
    ) {
        guard width > 0 else { return }

        let rect = cellRect(
            column: startColumn,
            row: rowIndex,
            width: width,
            metrics: metrics
        )
        let colors = resolvedColors(for: style, projection: projection)
        if fillsDefaultBackground || colors.background != defaultBackground {
            colors.background.setFill()
            UIRectFill(rect)
        }

        guard !text.isEmpty, !style.invisible else { return }
        let font = style.bold ? boldFont : regularFont
        let drawRect = GhosttySurfaceLayoutMetrics.textRect(for: rect, font: font)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: (accentForegroundColor ?? colors.foreground).withAlphaComponent(style.faint ? 0.6 : 1.0),
            .underlineStyle: style.underline == 0 ? 0 : NSUnderlineStyle.single.rawValue,
            .strikethroughStyle: style.strikethrough ? NSUnderlineStyle.single.rawValue : 0
        ]
        (text as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    private func drawCell(
        _ cell: GhosttyVTCellProjection,
        rowIndex: Int,
        projection: GhosttyVTRenderProjection,
        metrics: Metrics,
        fillsDefaultBackground: Bool,
        defaultBackground: UIColor,
        accentForegroundColor: UIColor?,
        regularFont: UIFont,
        boldFont: UIFont
    ) {
        let rect = cellRect(
            column: cell.column,
            row: rowIndex,
            width: cell.width == .wide ? 2 : 1,
            metrics: metrics
        )
        let colors = resolvedColors(for: cell.style, projection: projection)
        if fillsDefaultBackground || colors.background != defaultBackground {
            colors.background.setFill()
            UIRectFill(rect)
        }

        guard !cell.text.isEmpty, !cell.style.invisible else { return }
        let font = cell.style.bold ? boldFont : regularFont
        let drawRect = GhosttySurfaceLayoutMetrics.textRect(for: rect, font: font)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: (accentForegroundColor ?? colors.foreground).withAlphaComponent(cell.style.faint ? 0.6 : 1.0),
            .underlineStyle: cell.style.underline == 0 ? 0 : NSUnderlineStyle.single.rawValue,
            .strikethroughStyle: cell.style.strikethrough ? NSUnderlineStyle.single.rawValue : 0
        ]
        (cell.text as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    private func drawCursor(
        projection: GhosttyVTRenderProjection,
        metrics: Metrics,
        focused: Bool,
        cursorBlinkPhaseVisible: Bool
    ) {
        guard projection.cursor.visible else { return }
        guard !configuration.cursorBlink || cursorBlinkPhaseVisible else { return }
        guard let cursorX = projection.cursor.x, let cursorY = projection.cursor.y else { return }

        let rect = cellRect(
            column: cursorX,
            row: cursorY,
            width: projection.cursor.wideTail ? 2 : 1,
            metrics: metrics
        )
        let color = color(for: projection.cursorColor ?? projection.foregroundColor)
        color.withAlphaComponent(focused ? 0.85 : 0.45).setFill()
        color.setStroke()

        switch cursorVisualStyle {
        case .bar:
            UIBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)).fill()
        case .underline:
            UIBezierPath(rect: CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2)).fill()
        case .hollowBlock:
            let path = UIBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            path.lineWidth = 1.5
            path.stroke()
        case .block:
            UIBezierPath(rect: rect).fill()
        }
    }

    private func cellRect(
        column: Int,
        row: Int,
        width: Int,
        metrics: Metrics
    ) -> CGRect {
        CGRect(
            x: metrics.padding.left + (CGFloat(column) * metrics.cellSize.width),
            y: metrics.padding.top + (CGFloat(row) * metrics.cellSize.height),
            width: CGFloat(width) * metrics.cellSize.width,
            height: metrics.cellSize.height
        ).integral
    }

    private func resolvedColors(
        for style: GhosttyVTTextStyle,
        projection: GhosttyVTRenderProjection
    ) -> (foreground: UIColor, background: UIColor) {
        let defaultForeground = color(for: projection.foregroundColor)
        let defaultBackground = color(for: projection.backgroundColor)
        var foreground = color(
            for: style.foreground,
            palette: projection.palette,
            fallback: defaultForeground
        )
        var background = color(
            for: style.background,
            palette: projection.palette,
            fallback: defaultBackground
        )

        if style.inverse {
            swap(&foreground, &background)
        }

        if let accentForegroundColor = metricsPreset?.accentForegroundColor, style.bold {
            foreground = color(for: accentForegroundColor)
        }

        return (foreground, background)
    }

    private var cursorVisualStyle: GhosttyVTCursorVisualStyle {
        switch configuration.cursorStyle {
        case .block:
            return .block
        case .underline:
            return .underline
        case .bar:
            return .bar
        }
    }

    private func themedProjection(from projection: GhosttyVTRenderProjection) -> GhosttyVTRenderProjection {
        let theme = configuration.colorScheme.theme
        var projection = projection
        projection.backgroundColor = theme.background
        projection.foregroundColor = theme.foreground
        projection.cursorColor = theme.cursor
        projection.palette = theme.palette
        return projection
    }

    private func color(for color: GhosttyVTColor) -> UIColor {
        UIColor(
            red: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }

    private func color(
        for styleColor: GhosttyVTStyleColor,
        palette: [GhosttyVTColor],
        fallback: UIColor
    ) -> UIColor {
        switch styleColor {
        case .none:
            return fallback
        case .palette(let index):
            guard palette.indices.contains(Int(index)) else { return fallback }
            return color(for: palette[Int(index)])
        case .rgb(let color):
            return self.color(for: color)
        }
    }
}

private extension UIKeyModifierFlags {
    var ghosttyModifiers: GhosttyVTModifiers {
        var modifiers: GhosttyVTModifiers = []
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.control) { modifiers.insert(.control) }
        if contains(.alternate) { modifiers.insert(.alt) }
        if contains(.command) { modifiers.insert(.super) }
        if contains(.alphaShift) { modifiers.insert(.capsLock) }
        return modifiers
    }
}

private extension GhosttyVTModifiers {
    init(_ flags: UIKeyModifierFlags) {
        self = flags.ghosttyModifiers
    }
}

private extension UIKeyboardHIDUsage {
    var ghosttyKeyCode: GhosttyVTKeyCode? {
        switch self {
        case .keyboardA: return .a
        case .keyboardB: return .b
        case .keyboardC: return .c
        case .keyboardD: return .d
        case .keyboardE: return .e
        case .keyboardF: return .f
        case .keyboardG: return .g
        case .keyboardH: return .h
        case .keyboardI: return .i
        case .keyboardJ: return .j
        case .keyboardK: return .k
        case .keyboardL: return .l
        case .keyboardM: return .m
        case .keyboardN: return .n
        case .keyboardO: return .o
        case .keyboardP: return .p
        case .keyboardQ: return .q
        case .keyboardR: return .r
        case .keyboardS: return .s
        case .keyboardT: return .t
        case .keyboardU: return .u
        case .keyboardV: return .v
        case .keyboardW: return .w
        case .keyboardX: return .x
        case .keyboardY: return .y
        case .keyboardZ: return .z
        case .keyboard0: return .digit0
        case .keyboard1: return .digit1
        case .keyboard2: return .digit2
        case .keyboard3: return .digit3
        case .keyboard4: return .digit4
        case .keyboard5: return .digit5
        case .keyboard6: return .digit6
        case .keyboard7: return .digit7
        case .keyboard8: return .digit8
        case .keyboard9: return .digit9
        case .keyboardGraveAccentAndTilde: return .backquote
        case .keyboardBackslash: return .backslash
        case .keyboardOpenBracket: return .bracketLeft
        case .keyboardCloseBracket: return .bracketRight
        case .keyboardComma: return .comma
        case .keyboardEqualSign: return .equal
        case .keyboardHyphen: return .minus
        case .keyboardPeriod: return .period
        case .keyboardQuote: return .quote
        case .keyboardSemicolon: return .semicolon
        case .keyboardSlash: return .slash
        case .keyboardDeleteOrBackspace: return .backspace
        case .keyboardCapsLock: return .capsLock
        case .keyboardReturnOrEnter: return .enter
        case .keyboardSpacebar: return .space
        case .keyboardTab: return .tab
        case .keyboardDeleteForward: return .delete
        case .keyboardEnd: return .end
        case .keyboardHome: return .home
        case .keyboardInsert: return .insert
        case .keyboardPageDown: return .pageDown
        case .keyboardPageUp: return .pageUp
        case .keyboardDownArrow: return .arrowDown
        case .keyboardLeftArrow: return .arrowLeft
        case .keyboardRightArrow: return .arrowRight
        case .keyboardUpArrow: return .arrowUp
        case .keyboardEscape: return .escape
        case .keyboardLeftAlt: return .altLeft
        case .keyboardRightAlt: return .altRight
        case .keyboardLeftControl: return .controlLeft
        case .keyboardRightControl: return .controlRight
        case .keyboardLeftGUI: return .metaLeft
        case .keyboardRightGUI: return .metaRight
        case .keyboardLeftShift: return .shiftLeft
        case .keyboardRightShift: return .shiftRight
        case .keyboardF1: return .f1
        case .keyboardF2: return .f2
        case .keyboardF3: return .f3
        case .keyboardF4: return .f4
        case .keyboardF5: return .f5
        case .keyboardF6: return .f6
        case .keyboardF7: return .f7
        case .keyboardF8: return .f8
        case .keyboardF9: return .f9
        case .keyboardF10: return .f10
        case .keyboardF11: return .f11
        case .keyboardF12: return .f12
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#endif
