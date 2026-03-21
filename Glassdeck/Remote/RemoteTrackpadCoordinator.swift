#if canImport(UIKit)
import CoreGraphics
import Foundation
import GlassdeckCore
import UIKit

@MainActor
final class RemoteTrackpadCoordinator {
    private weak var session: SSHSessionModel?
    private weak var appSettings: AppSettings?

    private var scrollAccumulator: CGFloat = 0
    private var mouseDragIsActive = false

    func bind(session: SSHSessionModel, appSettings: AppSettings) {
        self.session = session
        self.appSettings = appSettings
    }

    func activate() {
        guard let session else { return }
        let initialMode = appSettings?.remoteTrackpadLastMode ?? .cursor
        setMode(initialMode, persist: false)
        session.remoteControlKeyboardFocused = true
    }

    func deactivate() {
        scrollAccumulator = 0
        mouseDragIsActive = false
        session?.remoteControlKeyboardFocused = false
        session?.remoteControlSoftwareKeyboardPresented = false
        session?.remoteControlUnsupportedMessage = nil
        session?.remotePointerOverlayState = .hidden
    }

    func setMode(_ mode: RemoteControlMode, persist: Bool = true) {
        guard let session else { return }
        session.remoteControlMode = mode
        if persist {
            appSettings?.remoteTrackpadLastMode = mode
        }

        switch mode {
        case .mouse:
            let point = currentPointerPoint()
            session.remotePointerOverlayState = overlayState(
                mode: .mouse,
                point: point,
                isVisible: true,
                isDragging: mouseDragIsActive
            )
        case .cursor:
            session.remotePointerOverlayState = .hidden
        }

        refreshUnsupportedMessage()
    }

    func toggleSoftwareKeyboard() {
        guard let session else { return }
        session.remoteControlSoftwareKeyboardPresented.toggle()
        session.remoteControlKeyboardFocused = true
    }

    func primaryTap(at location: CGPoint, in viewSize: CGSize) {
        guard let session else { return }

        switch session.remoteControlMode {
        case .mouse:
            let point = currentPointerPoint()
            if let surface = session.surface {
                _ = surface.sendRemoteMouse(action: .press, button: .left, surfacePixelPoint: point)
                _ = surface.sendRemoteMouse(action: .release, button: .left, surfacePixelPoint: point)
            }
            session.remotePointerOverlayState = overlayState(
                mode: .mouse,
                point: point,
                isVisible: true,
                isDragging: false
            )
        case .cursor:
            guard session.terminalInteractionCapabilities.supportsMousePlacement else {
                refreshUnsupportedMessage()
                return
            }
            guard let point = mappedSurfacePoint(for: location, in: viewSize) else { return }
            if let surface = session.surface {
                _ = surface.sendRemoteMouse(action: .motion, button: nil, surfacePixelPoint: point)
                _ = surface.sendRemoteMouse(action: .press, button: .left, surfacePixelPoint: point)
                _ = surface.sendRemoteMouse(action: .release, button: .left, surfacePixelPoint: point)
            }
            session.remotePointerOverlayState = .hidden
        }
    }

    func primaryPanChanged(location: CGPoint, translation: CGPoint, in viewSize: CGSize) {
        guard let session else { return }

        switch session.remoteControlMode {
        case .mouse:
            let point = advancedPointerPoint(by: translation, in: viewSize)
            if let surface = session.surface {
                _ = surface.sendRemoteMouse(action: .motion, button: nil, surfacePixelPoint: point)
            }
            session.remotePointerOverlayState = overlayState(
                mode: .mouse,
                point: point,
                isVisible: true,
                isDragging: mouseDragIsActive
            )
        case .cursor:
            guard session.terminalInteractionCapabilities.supportsMousePlacement else {
                refreshUnsupportedMessage()
                return
            }
            guard let point = mappedSurfacePoint(for: location, in: viewSize) else { return }
            session.remotePointerOverlayState = overlayState(
                mode: .cursor,
                point: point,
                isVisible: true,
                isDragging: false
            )
        }
    }

    func primaryPanEnded(location: CGPoint, cancelled: Bool, in viewSize: CGSize) {
        guard let session else { return }
        guard session.remoteControlMode == .cursor else { return }
        guard session.terminalInteractionCapabilities.supportsMousePlacement else {
            refreshUnsupportedMessage()
            session.remotePointerOverlayState = .hidden
            return
        }
        guard !cancelled, let point = mappedSurfacePoint(for: location, in: viewSize) else {
            session.remotePointerOverlayState = .hidden
            return
        }

        if let surface = session.surface {
            _ = surface.sendRemoteMouse(action: .motion, button: nil, surfacePixelPoint: point)
            _ = surface.sendRemoteMouse(action: .press, button: .left, surfacePixelPoint: point)
            _ = surface.sendRemoteMouse(action: .release, button: .left, surfacePixelPoint: point)
        }
        session.remotePointerOverlayState = .hidden
    }

    func secondaryTap(at location: CGPoint, in viewSize: CGSize) {
        guard let session, let surface = session.surface else { return }

        let point: CGPoint
        switch session.remoteControlMode {
        case .mouse:
            point = currentPointerPoint()
        case .cursor:
            guard session.terminalInteractionCapabilities.supportsMousePlacement else {
                refreshUnsupportedMessage()
                return
            }
            point = session.remotePointerOverlayState.isVisible
                ? session.remotePointerOverlayState.surfacePixelPoint
                : (mappedSurfacePoint(for: location, in: viewSize) ?? currentPointerPoint())
        }

        _ = surface.sendRemoteMouse(action: .press, button: .right, surfacePixelPoint: point)
        _ = surface.sendRemoteMouse(action: .release, button: .right, surfacePixelPoint: point)

        if session.remoteControlMode == .mouse {
            session.remotePointerOverlayState = overlayState(
                mode: .mouse,
                point: point,
                isVisible: true,
                isDragging: mouseDragIsActive
            )
        }
    }

    func scrollChanged(translationY: CGFloat, location: CGPoint, in viewSize: CGSize) {
        guard let session, let surface = session.surface else { return }
        guard session.terminalInteractionCapabilities.supportsScrollReporting else { return }

        scrollAccumulator += translationY
        let steps = Int(scrollAccumulator / 20)
        guard steps != 0 else { return }

        scrollAccumulator -= CGFloat(steps) * 20
        let point = resolvedInteractionPoint(location: location, in: viewSize)
        _ = surface.sendRemoteScroll(steps: steps, surfacePixelPoint: point)
    }

    func scrollEnded() {
        scrollAccumulator = 0
    }

    func dragHoldChanged(state: UIGestureRecognizer.State) {
        guard let session else { return }
        guard session.remoteControlMode == .mouse else { return }

        let point = currentPointerPoint()

        switch state {
        case .began:
            mouseDragIsActive = true
            if let surface = session.surface {
                _ = surface.sendRemoteMouse(action: .press, button: .left, surfacePixelPoint: point)
            }
            session.remotePointerOverlayState = overlayState(
                mode: .mouse,
                point: point,
                isVisible: true,
                isDragging: true
            )
        case .ended, .cancelled, .failed:
            guard mouseDragIsActive else { return }
            mouseDragIsActive = false
            if let surface = session.surface {
                _ = surface.sendRemoteMouse(action: .release, button: .left, surfacePixelPoint: point)
            }
            session.remotePointerOverlayState = overlayState(
                mode: .mouse,
                point: point,
                isVisible: true,
                isDragging: false
            )
        default:
            break
        }
    }

    var gestureHint: String {
        switch session?.remoteControlMode ?? .cursor {
        case .mouse:
            "Drag to move pointer. Tap to click. Hold to drag. Two fingers scroll or right-click."
        case .cursor:
            if session?.terminalInteractionCapabilities.supportsMousePlacement == true {
                "Tap to place the caret. Drag to preview placement. Two fingers scroll or right-click."
            } else {
                "Cursor placement is unavailable here. Two-finger scrolling still works when the app supports it."
            }
        }
    }

    var keyboardStatus: String {
        guard let session else { return "Keyboard unavailable" }
        return session.remoteControlSoftwareKeyboardPresented
            ? "Software keyboard active"
            : "Physical keyboard ready"
    }

    private func refreshUnsupportedMessage() {
        guard let session else { return }
        if session.remoteControlMode == .cursor,
           !session.terminalInteractionCapabilities.supportsMousePlacement {
            session.remoteControlUnsupportedMessage = "Cursor placement isn’t supported by the current terminal app."
        } else {
            session.remoteControlUnsupportedMessage = nil
        }
    }

    private func resolvedInteractionPoint(location: CGPoint, in viewSize: CGSize) -> CGPoint {
        if let mapped = mappedSurfacePoint(for: location, in: viewSize) {
            return mapped
        }
        return currentPointerPoint()
    }

    private func mappedSurfacePoint(for location: CGPoint, in viewSize: CGSize) -> CGPoint? {
        guard let geometry = geometry, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let fraction = CGPoint(
            x: max(0, min(location.x / viewSize.width, 1)),
            y: max(0, min(location.y / viewSize.height, 1))
        )
        return geometry.viewportPixelPoint(forFraction: fraction)
    }

    private func advancedPointerPoint(by translation: CGPoint, in viewSize: CGSize) -> CGPoint {
        guard let geometry = geometry, viewSize.width > 0, viewSize.height > 0 else {
            return currentPointerPoint()
        }

        let scaleX = CGFloat(geometry.viewportWidth) / max(viewSize.width, 1)
        let scaleY = CGFloat(geometry.viewportHeight) / max(viewSize.height, 1)
        let current = currentPointerPoint()
        return geometry.clampedViewportPixelPoint(
            CGPoint(
                x: current.x + (translation.x * scaleX),
                y: current.y + (translation.y * scaleY)
            )
        )
    }

    private func currentPointerPoint() -> CGPoint {
        guard let geometry else { return .zero }
        guard let session else { return geometry.viewportPixelPoint(forFraction: CGPoint(x: 0.5, y: 0.5)) }

        if session.remotePointerOverlayState.mode == .mouse || session.remotePointerOverlayState.isVisible {
            return geometry.clampedViewportPixelPoint(session.remotePointerOverlayState.surfacePixelPoint)
        }

        return geometry.viewportPixelPoint(forFraction: CGPoint(x: 0.5, y: 0.5))
    }

    private func overlayState(
        mode: RemoteControlMode,
        point: CGPoint,
        isVisible: Bool,
        isDragging: Bool
    ) -> RemotePointerOverlayState {
        let cellPosition = geometry?.cellPosition(forSurfacePixelPoint: point)
        return RemotePointerOverlayState(
            mode: mode,
            surfacePixelPoint: point,
            cellPosition: cellPosition,
            isVisible: isVisible,
            isDragging: isDragging
        )
    }

    private var geometry: RemoteTerminalGeometry? {
        guard let geometry = session?.terminalInteractionGeometry, geometry.isUsable else { return nil }
        return geometry
    }
}
#endif
