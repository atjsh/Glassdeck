#if canImport(UIKit)
import GlassdeckCore
import SwiftUI
import UIKit

struct RemoteTrackpadView: View {
    let session: SSHSessionModel

    @Environment(AppSettings.self) private var appSettings
    @State private var coordinator = RemoteTrackpadCoordinator()

    var body: some View {
        VStack(spacing: 14) {
            controlHeader

            if let message = session.remoteControlUnsupportedMessage {
                InlineStatusBanner(
                    label: message,
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                )
            }

            RemoteTrackpadInteractionView(session: session, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.9))
                )
                .overlay(alignment: .topLeading) {
                    Text(keyboardStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(16)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(gestureHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(16)
                }
                .overlay {
                    SessionKeyboardInputHost(
                        session: session,
                        isFocused: session.remoteControlKeyboardFocused,
                        softwareKeyboardPresented: session.remoteControlSoftwareKeyboardPresented
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                }
                .accessibilityIdentifier("remote-trackpad-view")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            coordinator.bind(session: session, appSettings: appSettings)
            coordinator.activate()
        }
        .onDisappear {
            coordinator.deactivate()
        }
        .onChange(of: session.remoteControlMode) { _, newValue in
            coordinator.setMode(newValue)
        }
    }

    private var controlHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("External Display Active")
                        .font(.headline)
                    Text("Use your iPhone as a trackpad while a physical keyboard types into SSH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    coordinator.toggleSoftwareKeyboard()
                } label: {
                    Label(
                        session.remoteControlSoftwareKeyboardPresented ? "Hide Keyboard" : "Keyboard",
                        systemImage: session.remoteControlSoftwareKeyboardPresented ? "keyboard.chevron.compact.down" : "keyboard"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("remote-keyboard-toggle")
            }

            Picker("Trackpad Mode", selection: Binding(
                get: { session.remoteControlMode },
                set: { coordinator.setMode($0) }
            )) {
                Text("Cursor").tag(RemoteControlMode.cursor)
                Text("Mouse").tag(RemoteControlMode.mouse)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("remote-mode-picker")
        }
    }

    private var keyboardStatus: String {
        session.remoteControlSoftwareKeyboardPresented
            ? "Software keyboard active"
            : "Physical keyboard ready"
    }

    private var gestureHint: String {
        switch session.remoteControlMode {
        case .mouse:
            "Drag to move the pointer. Tap to click. Hold to drag. Two fingers scroll or right-click."
        case .cursor:
            if session.terminalInteractionCapabilities.supportsMousePlacement {
                "Tap to place the caret. Drag to preview placement. Two fingers scroll or right-click."
            } else {
                "Cursor placement is unavailable here. Two-finger scrolling still works when the app supports it."
            }
        }
    }
}

private struct RemoteTrackpadInteractionView: UIViewRepresentable {
    let session: SSHSessionModel
    let coordinator: RemoteTrackpadCoordinator

    func makeUIView(context: Context) -> RemoteTrackpadInteractionSurface {
        let view = RemoteTrackpadInteractionSurface()
        view.configure(session: session, coordinator: coordinator)
        return view
    }

    func updateUIView(_ uiView: RemoteTrackpadInteractionSurface, context: Context) {
        uiView.configure(session: session, coordinator: coordinator)
    }
}

final class RemoteTrackpadInteractionSurface: UIView, UIGestureRecognizerDelegate {
    private weak var session: SSHSessionModel?
    private weak var trackpadCoordinator: RemoteTrackpadCoordinator?

    private lazy var singleTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        recognizer.numberOfTouchesRequired = 1
        return recognizer
    }()

    private lazy var secondaryTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleSecondaryTap(_:)))
        recognizer.numberOfTouchesRequired = 2
        return recognizer
    }()

    private lazy var primaryPanRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePrimaryPan(_:)))
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var scrollPanRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var dragHoldRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleDragHold(_:)))
        recognizer.minimumPressDuration = 0.25
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "remote-trackpad-surface"

        addGestureRecognizer(singleTapRecognizer)
        addGestureRecognizer(secondaryTapRecognizer)
        addGestureRecognizer(primaryPanRecognizer)
        addGestureRecognizer(scrollPanRecognizer)
        addGestureRecognizer(dragHoldRecognizer)

        singleTapRecognizer.require(toFail: primaryPanRecognizer)
        singleTapRecognizer.require(toFail: secondaryTapRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func configure(session: SSHSessionModel, coordinator: RemoteTrackpadCoordinator) {
        self.session = session
        self.trackpadCoordinator = coordinator
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === primaryPanRecognizer && otherGestureRecognizer === dragHoldRecognizer)
            || (gestureRecognizer === dragHoldRecognizer && otherGestureRecognizer === primaryPanRecognizer)
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        trackpadCoordinator?.primaryTap(at: recognizer.location(in: self), in: bounds.size)
    }

    @objc private func handleSecondaryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        trackpadCoordinator?.secondaryTap(at: recognizer.location(in: self), in: bounds.size)
    }

    @objc private func handlePrimaryPan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: self)
            trackpadCoordinator?.primaryPanChanged(
                location: location,
                translation: translation,
                in: bounds.size
            )
            recognizer.setTranslation(.zero, in: self)
        case .ended:
            trackpadCoordinator?.primaryPanEnded(
                location: location,
                cancelled: false,
                in: bounds.size
            )
            recognizer.setTranslation(.zero, in: self)
        case .cancelled, .failed:
            trackpadCoordinator?.primaryPanEnded(
                location: location,
                cancelled: true,
                in: bounds.size
            )
            recognizer.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    @objc private func handleScrollPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: self)
            trackpadCoordinator?.scrollChanged(
                translationY: translation.y,
                location: recognizer.location(in: self),
                in: bounds.size
            )
            recognizer.setTranslation(.zero, in: self)
        case .ended, .cancelled, .failed:
            trackpadCoordinator?.scrollEnded()
            recognizer.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    @objc private func handleDragHold(_ recognizer: UILongPressGestureRecognizer) {
        trackpadCoordinator?.dragHoldChanged(state: recognizer.state)
    }
}
#endif
