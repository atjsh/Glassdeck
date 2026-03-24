import Foundation
import GlassdeckCore
import SwiftUI

/// Protocol abstracting the terminal rendering engine.
/// The current concrete implementation is the Ghostty VT surface.
protocol TerminalEngine: Sendable {
    /// Write data received from SSH channel into the terminal
    func write(_ data: Data) async
    /// Read user input from the terminal to send to SSH channel
    func onInput(_ handler: @escaping @Sendable (Data) -> Void)
    /// Resize the terminal to the given dimensions
    func resize(columns: Int, rows: Int) async
    /// Current terminal dimensions
    var terminalSize: TerminalSize { get async }
}

/// SwiftUI terminal surface that renders the session-owned Ghostty VT surface.
struct TerminalSurfaceView: View {
    let session: SSHSessionModel

    private var exposesUITestInputProxy: Bool {
        UITestLaunchSupport.exposesTerminalRenderSummary
    }

    private var usesAnimationTerminalPresentation: Bool {
        UITestLaunchSupport.currentScenario == .animation
    }

    var body: some View {
        let connectedSurfaceInvariantBroken = session.isConnected
            && session.surface == nil
            && !session.isAwaitingSyntheticPreviewSurface
        let terminalRenderFailureReason = session.terminalRenderFailureReason
        let _ = Self.reportConnectedSurfaceInvariantViolation(
            for: session,
            isBroken: connectedSurfaceInvariantBroken
        )

        ZStack {
            if let surface = session.surface {
                if usesAnimationTerminalPresentation {
                    GhosttyPositionedTerminalView(
                        surface: surface,
                        isFocused: !exposesUITestInputProxy,
                        softwareKeyboardPresented: session.localTerminalSoftwareKeyboardPresented,
                        terminalSize: TerminalSize(
                            columns: GhosttyHomeAnimationSequence.expectedColumns,
                            rows: GhosttyHomeAnimationSequence.expectedRows
                        ),
                        configuration: GhosttyHomeAnimationSequence.testingTerminalConfiguration,
                        metricsPreset: GhosttyHomeAnimationSequence.testingMetricsPreset
                    )
                } else if surface.usesSyntheticTerminalBackend {
                    SyntheticTerminalPreview(surface: surface)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GhosttyTerminalViewWrapper(
                        surface: surface,
                        isFocused: session.isConnected,
                        softwareKeyboardPresented: session.localTerminalSoftwareKeyboardPresented
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let terminalRenderFailureReason, session.isConnected {
                    terminalUnavailableOverlay(reason: terminalRenderFailureReason)
                }
            } else {
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    statusIcon(connectedSurfaceInvariantBroken: connectedSurfaceInvariantBroken)
                    statusText(connectedSurfaceInvariantBroken: connectedSurfaceInvariantBroken)
                }
            }

            if !session.isConnected || connectedSurfaceInvariantBroken {
                statusOverlay(connectedSurfaceInvariantBroken: connectedSurfaceInvariantBroken)
            }
        }
        .overlay {
            ZStack {
                SessionKeyboardInputHost(
                    session: session,
                    isFocused: session.isConnected,
                    softwareKeyboardPresented: session.localTerminalSoftwareKeyboardPresented
                )
                .frame(
                    width: exposesUITestInputProxy ? 44 : 1,
                    height: exposesUITestInputProxy ? 44 : 1
                )
                .opacity(exposesUITestInputProxy ? 0.01 : 0.001)
                .clipped()

                Rectangle()
                    .fill(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("session-keyboard-state")
                    .accessibilityValue(session.localTerminalSoftwareKeyboardPresented ? "presented" : "hidden")
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                toggleLocalSoftwareKeyboardPresentation()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-surface-view")
    }

    private func toggleLocalSoftwareKeyboardPresentation() {
        guard session.isConnected else { return }
        let presented = !session.localTerminalSoftwareKeyboardPresented
        session.localTerminalSoftwareKeyboardPresented = presented
        session.surface?.setSoftwareKeyboardPresented(presented)
    }

    @ViewBuilder
    private func statusIcon(connectedSurfaceInvariantBroken: Bool) -> some View {
        if connectedSurfaceInvariantBroken {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
        } else {
            switch session.status {
            case .connecting, .authenticating, .reconnecting:
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
            case .disconnected:
                Image(systemName: "bolt.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func statusText(connectedSurfaceInvariantBroken: Bool) -> some View {
        VStack(spacing: 6) {
            Text(connectedSurfaceInvariantBroken ? "Terminal Unavailable" : session.status.label)
                .font(.body.monospaced())
                .foregroundStyle(.white.opacity(0.7))

            if connectedSurfaceInvariantBroken {
                Text("Connected session is missing a bound terminal surface.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private func terminalUnavailableOverlay(reason: String) -> some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Terminal Unavailable")
                    .font(.body.monospaced())
                    .foregroundStyle(.white.opacity(0.85))

                Text("Ghostty could not produce a render snapshot for this session.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text(reason)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func statusOverlay(connectedSurfaceInvariantBroken: Bool) -> some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: connectedSurfaceInvariantBroken ? "exclamationmark.triangle" : session.status.systemImage)
                Text(connectedSurfaceInvariantBroken ? "Terminal unavailable" : session.status.label)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 60)
        }
    }

    private static func reportConnectedSurfaceInvariantViolation(
        for session: SSHSessionModel,
        isBroken: Bool
    ) {
        guard isBroken else { return }
        let message = "Connected session \(session.id) is missing its GhosttySurface."
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            assertionFailure(message)
        } else {
            NSLog("%@", message)
        }
    }
}

/// UIViewRepresentable wrapper for an existing session-owned GhosttySurface.
struct GhosttyTerminalViewWrapper: UIViewRepresentable {
    let surface: GhosttySurface
    let isFocused: Bool
    let softwareKeyboardPresented: Bool

    func makeUIView(context: Context) -> GhosttyTerminalHostingView {
        let hostingView = GhosttyTerminalHostingView()
        hostingView.update(
            surface: surface,
            isFocused: isFocused,
            softwareKeyboardPresented: softwareKeyboardPresented
        )
        return hostingView
    }

    func updateUIView(_ uiView: GhosttyTerminalHostingView, context: Context) {
        uiView.update(
            surface: surface,
            isFocused: isFocused,
            softwareKeyboardPresented: softwareKeyboardPresented
        )
    }
}

final class GhosttyTerminalHostingView: UIView {
    private weak var hostedSurface: GhosttySurface?

    func update(surface: GhosttySurface, isFocused: Bool, softwareKeyboardPresented: Bool) {
        backgroundColor = terminalThemeColor(for: surface.terminalConfiguration.colorScheme)
        if hostedSurface !== surface {
            hostedSurface?.removeFromSuperview()
            hostedSurface = surface

            surface.removeFromSuperview()
            surface.translatesAutoresizingMaskIntoConstraints = true
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            surface.frame = bounds
            addSubview(surface)
            surface.setNeedsLayout()
            surface.layoutIfNeeded()
        }

        surface.setSoftwareKeyboardPresented(softwareKeyboardPresented)
        surface.setFocused(isFocused)
        surface.frame = bounds
        surface.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedSurface?.frame = bounds
    }
}

private func terminalThemeColor(for colorScheme: TerminalColorScheme) -> UIColor {
    let background = colorScheme.theme.background
    return UIColor(
        red: CGFloat(background.r) / 255,
        green: CGFloat(background.g) / 255,
        blue: CGFloat(background.b) / 255,
        alpha: 1
    )
}

struct GhosttyPositionedTerminalView: View {
    let surface: GhosttySurface
    let isFocused: Bool
    let softwareKeyboardPresented: Bool
    let terminalSize: TerminalSize
    let configuration: TerminalConfiguration
    let metricsPreset: GhosttySurfaceMetricsPreset?

    private var naturalBounds: CGRect {
        GhosttySurface.previewBounds(
            for: terminalSize,
            configuration: configuration,
            metricsPreset: metricsPreset
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                terminalContent
                .frame(
                    width: naturalBounds.width,
                    height: naturalBounds.height
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )
            }
            .clipped()
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if surface.usesSyntheticTerminalBackend {
            SyntheticTerminalPreview(surface: surface)
        } else {
            GhosttyTerminalViewWrapper(
                surface: surface,
                isFocused: isFocused,
                softwareKeyboardPresented: softwareKeyboardPresented
            )
        }
    }
}

private struct SyntheticTerminalPreview: View {
    let surface: GhosttySurface

    private var surfaceState: GhosttySurfaceState {
        surface.stateSnapshot
    }

    private var theme: TerminalTheme {
        surface.terminalConfiguration.colorScheme.theme
    }

    private var backgroundColor: Color {
        terminalColor(theme.background)
    }

    private var foregroundColor: Color {
        terminalColor(theme.foreground)
    }

    private var accentColor: Color {
        terminalColor(theme.palette.dropFirst(2).first ?? theme.cursor)
    }

    private var borderColor: Color {
        terminalColor(theme.palette.dropFirst(4).first ?? theme.cursor)
    }

    private var previewText: String {
        let summary = condensedTerminalPreviewText(surfaceState.visibleTextSummary)
        if !summary.isEmpty {
            return summary
        }

        if !surfaceState.presentationDebugSummary.isEmpty {
            return surfaceState.presentationDebugSummary
        }

        return "$ synthetic terminal ready"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        shape
            .fill(backgroundColor)
            .overlay {
                VStack(alignment: .leading, spacing: 0) {
                    headerBar
                    LinearGradient(
                        colors: [accentColor.opacity(0.95), borderColor.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 7)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(borderColor.opacity(0.28))
                            .frame(width: 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("$ glassdeck")
                                .font(.caption.monospaced())
                                .foregroundStyle(accentColor)

                            Text(previewText)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(foregroundColor)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .padding(16)
                    }
                }
            }
            .overlay {
                shape.stroke(borderColor.opacity(0.9), lineWidth: 2)
            }
            .clipShape(shape)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(terminalColor(theme.palette.dropFirst().first ?? theme.cursor))
                .frame(width: 10, height: 10)
            Circle()
                .fill(terminalColor(theme.palette.dropFirst(3).first ?? theme.cursor))
                .frame(width: 10, height: 10)
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            Spacer()

            Text(surfaceState.terminalSize.columns > 0 && surfaceState.terminalSize.rows > 0
                 ? "\(surfaceState.terminalSize.columns)x\(surfaceState.terminalSize.rows)"
                 : "synthetic")
                .font(.caption2.monospaced())
                .foregroundStyle(foregroundColor.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private func terminalColor(_ color: GhosttyVTColor) -> Color {
    Color(
        red: Double(color.r) / 255,
        green: Double(color.g) / 255,
        blue: Double(color.b) / 255
    )
}

private func condensedTerminalPreviewText(_ summary: String) -> String {
    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSummary.isEmpty else { return "" }

    let recentLines = trimmedSummary
        .split(whereSeparator: { $0.isNewline })
        .suffix(10)
        .map(String.init)
        .joined(separator: "\n")

    if recentLines.count <= 640 {
        return recentLines
    }

    return String(recentLines.suffix(640))
}
