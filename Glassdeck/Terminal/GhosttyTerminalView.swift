import AudioToolbox
import Foundation
import GhosttyKit
import GlassdeckCore
import Metal
import SwiftUI
import UIKit
import os

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
    let presentationDebugSummary: String
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

// MARK: - GhosttySurfaceError

enum GhosttySurfaceError: Error, LocalizedError {
    case appNotInitialized
    case surfaceCreationFailed

    var errorDescription: String? {
        switch self {
        case .appNotInitialized:
            return "GhosttyKit app is not initialized"
        case .surfaceCreationFailed:
            return "Failed to create GhosttyKit surface"
        }
    }
}

// MARK: - GhosttySurface

@MainActor
final class GhosttySurface: UIView, UIKeyInput, SessionKeyboardInputSink {
    private static let bellSoundID: SystemSoundID = 1103
    private static let debugTerminalInput = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let initialSurfaceFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
    private static let resizeDebounceInterval: Duration = .milliseconds(16)
    private static let logger = Logger(subsystem: "com.glassdeck", category: "GhosttyTerminalView")
    private static let syntheticTerminalEnvironmentKey = "GLASSDECK_UI_TEST_USE_SYNTHETIC_TERMINAL"

    private let configuration: TerminalConfiguration
    private let metricsPreset: GhosttySurfaceMetricsPreset?
    private let syntheticTerminalEnabled: Bool
    private var surface: ghostty_surface_t?
    private var ghosttyConfig: ghostty_config_t?
    let surfaceIO: GhosttyKitSurfaceIO

    private var currentTerminalSize = TerminalSize(columns: 80, rows: 24)
    private var currentPixelSize = TerminalPixelSize(width: 0, height: 0)
    private var currentCellPixelSize = TerminalPixelSize(width: 0, height: 0)
    private var currentPadding = UIEdgeInsets.zero
    private var currentDisplayScale: CGFloat = 1
    private var terminalIsFocused = false
    private var lastScrollRows = 0
    private var currentSoftwareKeyboardPresented = false
    private var resizeDebounceTask: Task<Void, Never>?
    private var pendingResizeSize: TerminalSize?
    private var pendingResizePixelSize: TerminalPixelSize?
    private(set) var renderCount = 0
    private var currentInteractionCapabilities = GhosttyVTInteractionCapabilities(
        supportsMousePlacement: false,
        supportsScrollReporting: false
    )
    private var currentAnimationProgress: GhosttyHomeAnimationProgress?
    private var currentAnimationAccentColumnsByRow: [Int: IndexSet]?
    private var titleObserver: NSObjectProtocol?
    private var bellObserver: NSObjectProtocol?
    private var syntheticVisibleTextSummary = ""

    var title: String?
    var isHealthy = true
    var cellSize: CGSize = .zero
    var onResize: ((Int, Int, TerminalPixelSize) -> Void)?
    var onStateChange: ((GhosttySurfaceState) -> Void)?
    var onSoftwareKeyboardPresentationChange: ((Bool) -> Void)?
    var terminalConfiguration: TerminalConfiguration {
        configuration
    }

    var usesSyntheticTerminalBackend: Bool {
        syntheticTerminalEnabled
    }

    override class var layerClass: AnyClass {
        CAMetalLayer.self
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
        var visibleTextSummary = ""
        if usesSyntheticTerminalBackend {
            visibleTextSummary = syntheticVisibleTextSummary
        } else if UITestLaunchSupport.exposesTerminalRenderSummary, let surface {
            visibleTextSummary = Self.readVisibleText(from: surface)
        }

        return GhosttySurfaceState(
            title: title,
            terminalSize: currentTerminalSize,
            pixelSize: pixelSize,
            scrollbackLines: configuration.scrollbackLines,
            isHealthy: isHealthy,
            renderFailureReason: usesSyntheticTerminalBackend || surface != nil ? nil : "Surface not created",
            visibleTextSummary: visibleTextSummary,
            hasRenderedFrame: renderCount > 0 && currentPixelSize.width > 0 && currentPixelSize.height > 0,
            animationProgress: currentAnimationProgress,
            interactionGeometry: interactionGeometry,
            interactionCapabilities: currentInteractionCapabilities,
            softwareKeyboardPresented: currentSoftwareKeyboardPresented,
            presentationDebugSummary: presentationDebugSummary()
        )
    }

    static func previewBounds(
        for terminalSize: TerminalSize,
        configuration: TerminalConfiguration = TerminalConfiguration(),
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

    var interactionGeometry: RemoteTerminalGeometry {
        RemoteTerminalGeometry(
            terminalSize: currentTerminalSize,
            surfacePixelSize: currentPixelSize,
            cellPixelSize: currentCellPixelSize,
            padding: RemoteControlInsets(
                top: Int((currentPadding.top * currentDisplayScale).rounded()),
                left: Int((currentPadding.left * currentDisplayScale).rounded()),
                bottom: Int((currentPadding.bottom * currentDisplayScale).rounded()),
                right: Int((currentPadding.right * currentDisplayScale).rounded())
            ),
            displayScale: Double(currentDisplayScale)
        )
    }

    init(
        configuration: TerminalConfiguration = TerminalConfiguration(),
        metricsPreset: GhosttySurfaceMetricsPreset? = nil
    ) throws {
        self.configuration = configuration
        self.metricsPreset = metricsPreset
        self.syntheticTerminalEnabled =
            ProcessInfo.processInfo.environment[Self.syntheticTerminalEnvironmentKey] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.surfaceIO = GhosttyKitSurfaceIO()
        super.init(frame: Self.initialSurfaceFrame)
        if !syntheticTerminalEnabled {
            try createSurface()
        }
        setupView()
        setupNotificationObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    isolated deinit {
        resizeDebounceTask?.cancel()
        if let titleObserver {
            NotificationCenter.default.removeObserver(titleObserver)
        }
        if let bellObserver {
            NotificationCenter.default.removeObserver(bellObserver)
        }
        surfaceIO.detach()
        if let surface {
            ghostty_surface_free(surface)
        }
        if let ghosttyConfig {
            ghostty_config_free(ghosttyConfig)
        }
    }

    override var canBecomeFirstResponder: Bool { false }

    override var canResignFirstResponder: Bool { false }

    var hasText: Bool {
        true
    }

    func writeToTerminal(_ data: Data) {
        if usesSyntheticTerminalBackend {
            appendSyntheticTranscript(data)
            return
        }
        guard let surface else { return }
        if configuration.bellSound, data.contains(0x07) {
            AudioServicesPlaySystemSound(Self.bellSoundID)
        }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            ghostty_surface_process_output(
                surface,
                ptr.assumingMemoryBound(to: CChar.self),
                UInt(buf.count)
            )
        }
        ghostty_surface_draw(surface)
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
        guard !usesSyntheticTerminalBackend else {
            publishState()
            return
        }
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
        publishState()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            terminalIsFocused = true
            if let surface {
                ghostty_surface_set_focus(surface, true)
            }
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            terminalIsFocused = false
            if let surface {
                ghostty_surface_set_focus(surface, false)
            }
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
    }

    override func removeFromSuperview() {
        resizeDebounceTask?.cancel()
        resizeDebounceTask = nil
        super.removeFromSuperview()
    }

    func insertText(_ text: String) {
        if usesSyntheticTerminalBackend {
            guard !text.isEmpty else { return }
            debugLog("insertText \(Self.debugDescription(for: text))")
            surfaceIO.emitInput(Data(text.utf8))
            return
        }
        guard let surface, !text.isEmpty else { return }
        debugLog("insertText \(Self.debugDescription(for: text))")
        text.withCString { cstr in
            ghostty_surface_write_no_encode(surface, cstr, UInt(text.utf8.count))
        }
    }

    func deleteBackward() {
        if usesSyntheticTerminalBackend {
            debugLog("deleteBackward")
            surfaceIO.emitInput(Data("\u{7f}".utf8))
            return
        }
        guard let surface else { return }
        debugLog("deleteBackward")
        let del = "\u{7f}"
        del.withCString { cstr in
            ghostty_surface_write_no_encode(surface, cstr, UInt(del.utf8.count))
        }
    }

    func setMarkedText(_ markedText: String?) {
        guard !usesSyntheticTerminalBackend else { return }
        guard let surface else { return }
        if let markedText, !markedText.isEmpty {
            markedText.withCString { cstr in
                ghostty_surface_preedit(surface, cstr, UInt(markedText.utf8.count))
            }
        } else {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func unmarkText() {
        guard !usesSyntheticTerminalBackend else { return }
        guard let surface else { return }
        ghostty_surface_preedit(surface, nil, 0)
    }

    func cursorRectForIME() -> CGRect {
        guard let surface else { return .zero }
        var x: Double = 0
        var y: Double = 0
        var w: Double = 0
        var h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        return CGRect(x: x, y: y, width: w, height: h).integral
    }

    override func paste(_ sender: Any?) {
        if usesSyntheticTerminalBackend, let string = UIPasteboard.general.string, !string.isEmpty {
            debugLog("paste \(Self.debugDescription(for: string))")
            surfaceIO.emitInput(Data(string.utf8))
            return
        }
        guard let surface, let string = UIPasteboard.general.string else { return }
        debugLog("paste \(Self.debugDescription(for: string))")
        string.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(string.utf8.count))
        }
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

    func updateConfiguration(_ config: TerminalConfiguration) {
        guard let surface else { return }
        guard let newConfig = Self.createGhosttyConfig(for: config) else { return }
        if let oldConfig = ghosttyConfig {
            ghostty_config_free(oldConfig)
        }
        ghosttyConfig = newConfig
        ghostty_surface_update_config(surface, newConfig)
    }

    enum RemoteMouseAction {
        case press
        case release
        case motion
    }

    enum RemoteMouseButton {
        case left
        case right
    }

    func sendRemoteMouse(
        action: RemoteMouseAction,
        button: RemoteMouseButton?,
        surfacePixelPoint: CGPoint
    ) -> Bool {
        guard let surface else { return false }
        guard currentPixelSize.width > 0, currentPixelSize.height > 0 else { return false }

        let scale = currentDisplayScale
        let x = surfacePixelPoint.x / scale
        let y = surfacePixelPoint.y / scale

        switch action {
        case .motion:
            ghostty_surface_mouse_pos(surface, x, y, GHOSTTY_MODS_NONE)
            return true
        case .press, .release:
            let ghosttyButton: ghostty_input_mouse_button_e
            switch button {
            case .left, .none: ghosttyButton = GHOSTTY_MOUSE_LEFT
            case .right: ghosttyButton = GHOSTTY_MOUSE_RIGHT
            }
            let ghosttyAction: ghostty_input_mouse_state_e = action == .press
                ? GHOSTTY_MOUSE_PRESS
                : GHOSTTY_MOUSE_RELEASE
            ghostty_surface_mouse_pos(surface, x, y, GHOSTTY_MODS_NONE)
            let captured = ghostty_surface_mouse_button(
                surface,
                ghosttyAction,
                ghosttyButton,
                GHOSTTY_MODS_NONE
            )
            return captured
        }
    }

    func sendRemoteScroll(steps: Int, surfacePixelPoint: CGPoint) -> Bool {
        guard let surface else { return false }
        guard steps != 0 else { return false }
        guard currentInteractionCapabilities.supportsScrollReporting else { return false }

        let scale = currentDisplayScale
        let x = surfacePixelPoint.x / scale
        let y = surfacePixelPoint.y / scale

        ghostty_surface_mouse_pos(surface, x, y, GHOSTTY_MODS_NONE)
        let scrollY = Double(steps)
        ghostty_surface_mouse_scroll(surface, 0, scrollY, 0)
        return true
    }

    enum KeyAction {
        case press
        case release

        var ghosttyAction: ghostty_input_action_e {
            switch self {
            case .press: return GHOSTTY_ACTION_PRESS
            case .release: return GHOSTTY_ACTION_RELEASE
            }
        }
    }

    @discardableResult
    func handleHardwarePresses(
        _ presses: Set<UIPress>,
        action: KeyAction
    ) -> Set<UIPress> {
        if usesSyntheticTerminalBackend {
            return handleSyntheticHardwarePresses(presses, action: action)
        }

        guard let surface else { return presses }
        var unhandled = Set<UIPress>()
        let ghosttyAction = action.ghosttyAction

        for press in presses {
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }

            let ghosttyKey = key.keyCode.ghosttyInputKey
            if ghosttyKey == GHOSTTY_KEY_UNIDENTIFIED && (action == .release || key.characters.isEmpty) {
                unhandled.insert(press)
                continue
            }

            var keyEvent = ghostty_input_key_s()
            keyEvent.action = ghosttyAction
            keyEvent.mods = key.modifierFlags.ghosttyInputMods
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.keycode = UInt32(ghosttyKey.rawValue)
            keyEvent.composing = false

            let chars = key.characters
            if action != .release, !chars.isEmpty {
                let handled: Bool = chars.withCString { cstr in
                    keyEvent.text = cstr
                    return ghostty_surface_key(surface, keyEvent)
                }
                if !handled {
                    unhandled.insert(press)
                }
            } else {
                keyEvent.text = nil
                let handled = ghostty_surface_key(surface, keyEvent)
                if !handled {
                    unhandled.insert(press)
                }
            }
        }

        return unhandled
    }

    // MARK: - Private

    private func createSurface() throws {
        guard let app = GhosttyKitApp.shared.app else {
            throw GhosttySurfaceError.appNotInitialized
        }

        let config = Self.createGhosttyConfig(for: configuration)
        ghosttyConfig = config

        var surfaceCfg = ghostty_surface_config_new()
        surfaceCfg.platform_tag = GHOSTTY_PLATFORM_IOS
        surfaceCfg.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(
            uiview: Unmanaged.passUnretained(self).toOpaque()
        ))
        surfaceCfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceCfg.scale_factor = Double(UIScreen.main.scale)
        surfaceCfg.font_size = Float(configuration.fontSize)

        guard let newSurface = ghostty_surface_new(app, &surfaceCfg) else {
            throw GhosttySurfaceError.surfaceCreationFailed
        }

        self.surface = newSurface
        surfaceIO.configure(surface: newSurface)
        ghostty_surface_set_focus(newSurface, terminalIsFocused)
    }

    private func setupView() {
        backgroundColor = Self.color(for: configuration.colorScheme.theme.background)
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityIdentifier = "ghostty-terminal-surface"
        accessibilityTraits.insert(.allowsDirectInteraction)

        guard !usesSyntheticTerminalBackend else { return }

        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = traitCollection.displayScale

        let scrollRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        scrollRecognizer.minimumNumberOfTouches = 2
        scrollRecognizer.maximumNumberOfTouches = 2
        addGestureRecognizer(scrollRecognizer)

        if #available(iOS 13.4, *) {
            let hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            addGestureRecognizer(hoverRecognizer)
        }
    }

    private func setupNotificationObservers() {
        titleObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyKitSurfaceTitleChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let surfacePtr = notification.object as? OpaquePointer,
                  UnsafeMutableRawPointer(surfacePtr) == self.surface else { return }
            if let title = notification.userInfo?["title"] as? String {
                self.title = title
                self.publishState()
            }
        }

        bellObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyKitBellRung,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let surfacePtr = notification.object as? OpaquePointer {
                guard UnsafeMutableRawPointer(surfacePtr) == self.surface else { return }
            }
            if self.configuration.bellSound {
                AudioServicesPlaySystemSound(Self.bellSoundID)
            }
        }
    }

    @objc private func handleScrollPan(_ recognizer: UIPanGestureRecognizer) {
        guard let surface else { return }
        guard currentCellPixelSize.height > 0 else { return }

        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            recognizer.setTranslation(.zero, in: self)
            lastScrollRows = 0
            return
        }

        let translation = recognizer.translation(in: self)
        let cellHeight = CGFloat(currentCellPixelSize.height) / currentDisplayScale
        let rowDelta = Int(translation.y / cellHeight)
        guard rowDelta != lastScrollRows else { return }

        let delta = Double(rowDelta - lastScrollRows)
        lastScrollRows = rowDelta
        ghostty_surface_mouse_scroll(surface, 0, delta, 0)
    }

    @available(iOS 13.4, *)
    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard let surface else { return }
        let location = recognizer.location(in: self)
        ghostty_surface_mouse_pos(surface, location.x, location.y, GHOSTTY_MODS_NONE)
    }

    private func syncHostedLayerGeometry(scale: CGFloat) {
        guard let hostedLayers = metalLayer.sublayers, !hostedLayers.isEmpty else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for hostedLayer in hostedLayers {
            hostedLayer.frame = bounds
            hostedLayer.contentsScale = scale
            hostedLayer.setNeedsDisplay()
        }
        CATransaction.commit()
    }

    private func updateLayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if usesSyntheticTerminalBackend {
            updateSyntheticLayout()
            return
        }
        guard let surface else { return }

        let scale = traitCollection.displayScale
        currentDisplayScale = scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        syncHostedLayerGeometry(scale: scale)

        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        ghostty_surface_set_size(
            surface,
            UInt32((bounds.width * scale).rounded()),
            UInt32((bounds.height * scale).rounded())
        )

        ghostty_surface_draw(surface)
        renderCount += 1

        let sizeInfo = ghostty_surface_size(surface)
        let newTerminalSize = TerminalSize(
            columns: Int(sizeInfo.columns),
            rows: Int(sizeInfo.rows)
        )
        let newPixelSize = TerminalPixelSize(
            width: Int(sizeInfo.width_px),
            height: Int(sizeInfo.height_px)
        )
        let newCellPixelSize = TerminalPixelSize(
            width: Int(sizeInfo.cell_width_px),
            height: Int(sizeInfo.cell_height_px)
        )

        let displayMode = GhosttySurfaceLayoutMetrics.displayMode(for: window?.windowScene)
        let basePadding = GhosttySurfaceLayoutMetrics.basePadding(
            for: bounds,
            mode: displayMode,
            metricsPreset: metricsPreset
        )
        let cellSizePt: CGSize
        if sizeInfo.cell_width_px > 0, sizeInfo.cell_height_px > 0 {
            cellSizePt = CGSize(
                width: CGFloat(sizeInfo.cell_width_px) / scale,
                height: CGFloat(sizeInfo.cell_height_px) / scale
            )
        } else {
            cellSizePt = GhosttySurfaceLayoutMetrics.cellSize(
                for: configuration,
                mode: displayMode,
                metricsPreset: metricsPreset
            )
        }

        let contentWidth = CGFloat(newTerminalSize.columns) * cellSizePt.width
        let contentHeight = CGFloat(newTerminalSize.rows) * cellSizePt.height
        let extraHorizontal = max(0, bounds.width - basePadding.left - basePadding.right - contentWidth)
        let extraVertical = max(0, bounds.height - basePadding.top - basePadding.bottom - contentHeight)
        currentPadding = UIEdgeInsets(
            top: basePadding.top + floor(extraVertical / 2),
            left: basePadding.left + floor(extraHorizontal / 2),
            bottom: basePadding.bottom + ceil(extraVertical / 2),
            right: basePadding.right + ceil(extraHorizontal / 2)
        )

        cellSize = cellSizePt

        let previousTerminalSize = currentTerminalSize
        let previousPixelSize = currentPixelSize

        currentCellPixelSize = newCellPixelSize

        let sizeChanged = newTerminalSize != previousTerminalSize || newPixelSize != previousPixelSize

        let captured = ghostty_surface_mouse_captured(surface)
        currentInteractionCapabilities = GhosttyVTInteractionCapabilities(
            supportsMousePlacement: captured,
            supportsScrollReporting: captured
        )

        guard sizeChanged else {
            publishState()
            return
        }

        scheduleResize(size: newTerminalSize, pixelSize: newPixelSize)
    }

    private func scheduleResize(
        size: TerminalSize,
        pixelSize: TerminalPixelSize
    ) {
        pendingResizeSize = size
        pendingResizePixelSize = pixelSize

        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resizeDebounceInterval)
            guard !Task.isCancelled, let self else { return }
            guard let size = self.pendingResizeSize else { return }
            self.applyResize(
                size: size,
                pixelSize: self.pendingResizePixelSize
            )
            self.pendingResizeSize = nil
        }
    }

    private func applyResize(
        size: TerminalSize,
        pixelSize: TerminalPixelSize?
    ) {
        currentTerminalSize = size
        if let pixelSize {
            currentPixelSize = pixelSize
        }

        onResize?(
            size.columns,
            size.rows,
            pixelSize ?? currentPixelSize
        )
        publishState()
    }

    private func publishState() {
        onStateChange?(stateSnapshot)
    }

    func clearSyntheticTranscript() {
        guard usesSyntheticTerminalBackend else { return }
        syntheticVisibleTextSummary = ""
        publishState()
    }

    func prepareSyntheticPresentationIfNeeded() {
        guard usesSyntheticTerminalBackend else { return }
        guard currentPixelSize.width == 0 || currentPixelSize.height == 0 || renderCount == 0 else {
            return
        }
        if bounds.width <= 0 || bounds.height <= 0 {
            frame = Self.initialSurfaceFrame
        }
        updateSyntheticLayout()
        if let size = pendingResizeSize {
            resizeDebounceTask?.cancel()
            resizeDebounceTask = nil
            applyResize(size: size, pixelSize: pendingResizePixelSize)
            pendingResizeSize = nil
            pendingResizePixelSize = nil
        }
    }

    private func presentationDebugSummary() -> String {
        let scale = max(currentDisplayScale, 1)
        let drawableSize = metalLayer.drawableSize
        let hostedLayers = metalLayer.sublayers ?? []
        let firstHostedLayerFrame = hostedLayers.first?.frame ?? .zero
        let firstHostedLayerBounds = hostedLayers.first?.bounds ?? .zero

        return [
            "view=\(Int(bounds.width.rounded()))x\(Int(bounds.height.rounded()))",
            "scale=\(String(format: "%.2f", scale))",
            "drawable=\(Int(drawableSize.width.rounded()))x\(Int(drawableSize.height.rounded()))",
            "sublayers=\(hostedLayers.count)",
            "firstFrame=\(Int(firstHostedLayerFrame.width.rounded()))x\(Int(firstHostedLayerFrame.height.rounded()))",
            "firstBounds=\(Int(firstHostedLayerBounds.width.rounded()))x\(Int(firstHostedLayerBounds.height.rounded()))",
            "renderCount=\(renderCount)",
            "window=\(window == nil ? 0 : 1)",
        ].joined(separator: " ")
    }

    private static func readVisibleText(from surface: ghostty_surface_t) -> String {
        let sizeInfo = ghostty_surface_size(surface)
        guard sizeInfo.columns > 0, sizeInfo.rows > 0 else { return "" }

        var topLeft = ghostty_point_s()
        topLeft.tag = GHOSTTY_POINT_VIEWPORT
        topLeft.coord = GHOSTTY_POINT_COORD_TOP_LEFT
        topLeft.x = 0
        topLeft.y = 0

        var bottomRight = ghostty_point_s()
        bottomRight.tag = GHOSTTY_POINT_VIEWPORT
        bottomRight.coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT
        bottomRight.x = UInt32(sizeInfo.columns) - 1
        bottomRight.y = UInt32(sizeInfo.rows) - 1

        var selection = ghostty_selection_s()
        selection.top_left = topLeft
        selection.bottom_right = bottomRight
        selection.rectangle = false

        var textResult = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &textResult) else {
            return ""
        }
        defer { ghostty_surface_free_text(surface, &textResult) }

        guard let ptr = textResult.text, textResult.text_len > 0 else {
            return ""
        }
        return String(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr),
            length: Int(textResult.text_len),
            encoding: .utf8,
            freeWhenDone: false
        ) ?? ""
    }

    private func appendSyntheticTranscript(_ data: Data) {
        let rendered = String(decoding: data, as: UTF8.self)
        if !rendered.isEmpty {
            syntheticVisibleTextSummary.append(rendered)
            syntheticVisibleTextSummary = Self.condensedSyntheticSummary(syntheticVisibleTextSummary)
        }
        renderCount += 1
        publishState()
    }

    private func updateSyntheticLayout() {
        let scale = max(traitCollection.displayScale, 1)
        currentDisplayScale = scale

        let displayMode = GhosttySurfaceLayoutMetrics.displayMode(for: window?.windowScene)
        let resolvedCellSize = GhosttySurfaceLayoutMetrics.cellSize(
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
        let columns = max(1, Int(floor(usableWidth / resolvedCellSize.width)))
        let rows = max(1, Int(floor(usableHeight / resolvedCellSize.height)))
        let contentWidth = CGFloat(columns) * resolvedCellSize.width
        let contentHeight = CGFloat(rows) * resolvedCellSize.height
        let extraHorizontal = max(0, bounds.width - basePadding.left - basePadding.right - contentWidth)
        let extraVertical = max(0, bounds.height - basePadding.top - basePadding.bottom - contentHeight)

        cellSize = resolvedCellSize
        currentPadding = UIEdgeInsets(
            top: basePadding.top + floor(extraVertical / 2),
            left: basePadding.left + floor(extraHorizontal / 2),
            bottom: basePadding.bottom + ceil(extraVertical / 2),
            right: basePadding.right + ceil(extraHorizontal / 2)
        )

        let newTerminalSize = TerminalSize(columns: columns, rows: rows)
        let newPixelSize = TerminalPixelSize(
            width: Int((bounds.width * scale).rounded()),
            height: Int((bounds.height * scale).rounded())
        )
        let newCellPixelSize = TerminalPixelSize(
            width: Int((resolvedCellSize.width * scale).rounded()),
            height: Int((resolvedCellSize.height * scale).rounded())
        )
        let sizeChanged = newTerminalSize != currentTerminalSize || newPixelSize != currentPixelSize
        currentCellPixelSize = newCellPixelSize
        renderCount += 1

        guard sizeChanged else {
            publishState()
            return
        }

        scheduleResize(size: newTerminalSize, pixelSize: newPixelSize)
    }

    private func handleSyntheticHardwarePresses(
        _ presses: Set<UIPress>,
        action: KeyAction
    ) -> Set<UIPress> {
        guard action == .press else { return [] }

        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }

            let characters = key.charactersIgnoringModifiers.isEmpty
                ? key.characters
                : key.charactersIgnoringModifiers
            if characters.isEmpty {
                unhandled.insert(press)
                continue
            }

            surfaceIO.emitInput(Data(characters.utf8))
        }
        return unhandled
    }

    private static func condensedSyntheticSummary(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.count <= 2_048 {
            return trimmed
        }

        return String(trimmed.suffix(2_048))
    }

    private static func createGhosttyConfig(for terminal: TerminalConfiguration) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }

        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("ghostty-glassdeck-\(UUID().uuidString).conf")

        var lines: [String] = []
        lines.append("font-family = \(terminal.fontFamily)")
        lines.append("font-size = \(Int(terminal.fontSize))")

        let theme = terminal.colorScheme.theme
        lines.append("background = \(theme.background.hexString)")
        lines.append("foreground = \(theme.foreground.hexString)")
        lines.append("cursor-color = \(theme.cursor.hexString)")

        for (i, color) in theme.palette.prefix(256).enumerated() {
            lines.append("palette = \(i)=\(color.hexString)")
        }

        let cursorStyle: String = switch terminal.cursorStyle {
        case .block: "block"
        case .underline: "underline"
        case .bar: "bar"
        }
        lines.append("cursor-style = \(cursorStyle)")
        lines.append("cursor-style-blink = \(terminal.cursorBlink)")
        lines.append("scrollback-limit = \(terminal.scrollbackLines)")
        lines.append("command = /bin/cat")
        lines.append("wait-after-command = false")

        do {
            try lines.joined(separator: "\n").write(to: tmpFile, atomically: true, encoding: .utf8)
            ghostty_config_load_file(config, tmpFile.path)
            try? FileManager.default.removeItem(at: tmpFile)
        } catch {
            try? FileManager.default.removeItem(at: tmpFile)
        }

        ghostty_config_finalize(config)
        return config
    }

    private static func color(for color: GhosttyVTColor) -> UIColor {
        UIColor(
            red: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
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
            if resolvedCount >= cellCount {
                return dimension
            }
            dimension += 1
        }
        return dimension
    }
}

// MARK: - GhosttySurfaceTerminalIO

final class GhosttySurfaceTerminalIO: TerminalIO, @unchecked Sendable {
    private let io: GhosttyKitSurfaceIO
    private weak var surface: GhosttySurface?

    init(surface: GhosttySurface) {
        self.surface = surface
        self.io = surface.surfaceIO
    }

    func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) async {
        await io.setOutputHandler(handler)
    }

    func write(_ data: Data) async {
        await MainActor.run {
            surface?.writeToTerminal(data)
        }
    }
}

// MARK: - UIKeyModifierFlags → ghostty_input_mods_e

private extension UIKeyModifierFlags {
    var ghosttyInputMods: ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if contains(.alternate) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if contains(.alphaShift) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }
}

// MARK: - UIKeyboardHIDUsage → ghostty_input_key_e

private extension UIKeyboardHIDUsage {
    var ghosttyInputKey: ghostty_input_key_e {
        switch self {
        case .keyboardA: return GHOSTTY_KEY_A
        case .keyboardB: return GHOSTTY_KEY_B
        case .keyboardC: return GHOSTTY_KEY_C
        case .keyboardD: return GHOSTTY_KEY_D
        case .keyboardE: return GHOSTTY_KEY_E
        case .keyboardF: return GHOSTTY_KEY_F
        case .keyboardG: return GHOSTTY_KEY_G
        case .keyboardH: return GHOSTTY_KEY_H
        case .keyboardI: return GHOSTTY_KEY_I
        case .keyboardJ: return GHOSTTY_KEY_J
        case .keyboardK: return GHOSTTY_KEY_K
        case .keyboardL: return GHOSTTY_KEY_L
        case .keyboardM: return GHOSTTY_KEY_M
        case .keyboardN: return GHOSTTY_KEY_N
        case .keyboardO: return GHOSTTY_KEY_O
        case .keyboardP: return GHOSTTY_KEY_P
        case .keyboardQ: return GHOSTTY_KEY_Q
        case .keyboardR: return GHOSTTY_KEY_R
        case .keyboardS: return GHOSTTY_KEY_S
        case .keyboardT: return GHOSTTY_KEY_T
        case .keyboardU: return GHOSTTY_KEY_U
        case .keyboardV: return GHOSTTY_KEY_V
        case .keyboardW: return GHOSTTY_KEY_W
        case .keyboardX: return GHOSTTY_KEY_X
        case .keyboardY: return GHOSTTY_KEY_Y
        case .keyboardZ: return GHOSTTY_KEY_Z
        case .keyboard0: return GHOSTTY_KEY_DIGIT_0
        case .keyboard1: return GHOSTTY_KEY_DIGIT_1
        case .keyboard2: return GHOSTTY_KEY_DIGIT_2
        case .keyboard3: return GHOSTTY_KEY_DIGIT_3
        case .keyboard4: return GHOSTTY_KEY_DIGIT_4
        case .keyboard5: return GHOSTTY_KEY_DIGIT_5
        case .keyboard6: return GHOSTTY_KEY_DIGIT_6
        case .keyboard7: return GHOSTTY_KEY_DIGIT_7
        case .keyboard8: return GHOSTTY_KEY_DIGIT_8
        case .keyboard9: return GHOSTTY_KEY_DIGIT_9
        case .keyboardGraveAccentAndTilde: return GHOSTTY_KEY_BACKQUOTE
        case .keyboardBackslash: return GHOSTTY_KEY_BACKSLASH
        case .keyboardOpenBracket: return GHOSTTY_KEY_BRACKET_LEFT
        case .keyboardCloseBracket: return GHOSTTY_KEY_BRACKET_RIGHT
        case .keyboardComma: return GHOSTTY_KEY_COMMA
        case .keyboardEqualSign: return GHOSTTY_KEY_EQUAL
        case .keyboardHyphen: return GHOSTTY_KEY_MINUS
        case .keyboardPeriod: return GHOSTTY_KEY_PERIOD
        case .keyboardQuote: return GHOSTTY_KEY_QUOTE
        case .keyboardSemicolon: return GHOSTTY_KEY_SEMICOLON
        case .keyboardSlash: return GHOSTTY_KEY_SLASH
        case .keyboardDeleteOrBackspace: return GHOSTTY_KEY_BACKSPACE
        case .keyboardCapsLock: return GHOSTTY_KEY_CAPS_LOCK
        case .keyboardReturnOrEnter: return GHOSTTY_KEY_ENTER
        case .keyboardSpacebar: return GHOSTTY_KEY_SPACE
        case .keyboardTab: return GHOSTTY_KEY_TAB
        case .keyboardDeleteForward: return GHOSTTY_KEY_DELETE
        case .keyboardEnd: return GHOSTTY_KEY_END
        case .keyboardHome: return GHOSTTY_KEY_HOME
        case .keyboardInsert: return GHOSTTY_KEY_INSERT
        case .keyboardPageDown: return GHOSTTY_KEY_PAGE_DOWN
        case .keyboardPageUp: return GHOSTTY_KEY_PAGE_UP
        case .keyboardDownArrow: return GHOSTTY_KEY_ARROW_DOWN
        case .keyboardLeftArrow: return GHOSTTY_KEY_ARROW_LEFT
        case .keyboardRightArrow: return GHOSTTY_KEY_ARROW_RIGHT
        case .keyboardUpArrow: return GHOSTTY_KEY_ARROW_UP
        case .keyboardEscape: return GHOSTTY_KEY_ESCAPE
        case .keyboardLeftAlt: return GHOSTTY_KEY_ALT_LEFT
        case .keyboardRightAlt: return GHOSTTY_KEY_ALT_RIGHT
        case .keyboardLeftControl: return GHOSTTY_KEY_CONTROL_LEFT
        case .keyboardRightControl: return GHOSTTY_KEY_CONTROL_RIGHT
        case .keyboardLeftGUI: return GHOSTTY_KEY_META_LEFT
        case .keyboardRightGUI: return GHOSTTY_KEY_META_RIGHT
        case .keyboardLeftShift: return GHOSTTY_KEY_SHIFT_LEFT
        case .keyboardRightShift: return GHOSTTY_KEY_SHIFT_RIGHT
        case .keyboardF1: return GHOSTTY_KEY_F1
        case .keyboardF2: return GHOSTTY_KEY_F2
        case .keyboardF3: return GHOSTTY_KEY_F3
        case .keyboardF4: return GHOSTTY_KEY_F4
        case .keyboardF5: return GHOSTTY_KEY_F5
        case .keyboardF6: return GHOSTTY_KEY_F6
        case .keyboardF7: return GHOSTTY_KEY_F7
        case .keyboardF8: return GHOSTTY_KEY_F8
        case .keyboardF9: return GHOSTTY_KEY_F9
        case .keyboardF10: return GHOSTTY_KEY_F10
        case .keyboardF11: return GHOSTTY_KEY_F11
        case .keyboardF12: return GHOSTTY_KEY_F12
        default:
            return GHOSTTY_KEY_UNIDENTIFIED
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension GhosttySurface {
    func debugLog(_ message: String) {
        guard Self.debugTerminalInput else { return }
        NSLog("GhosttySurface %@", message)
    }

    static func debugDescription(for text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
