import SwiftUI
import UIKit

// NOTE: Requires GhosttyKit.xcframework in Frameworks/
// Build from https://github.com/ghostty-org/ghostty using:
//   ./macos/build.nu --scheme Ghostty-iOS --configuration Release --action build
//
// When GhosttyKit is not available, the app falls back to SwiftTerm.
// Uncomment `import GhosttyKit` once the framework is embedded.

// import GhosttyKit

// MARK: - GhosttyKit App Wrapper

/// Wraps the Ghostty terminal engine lifecycle.
///
/// Manages the `ghostty_app_t` instance and runtime configuration.
/// On iOS, clipboard and action callbacks have basic implementations.
@Observable
final class GhosttyApp {
    enum Readiness: Sendable {
        case loading
        case ready
        case error
    }

    private(set) var readiness: Readiness = .loading

    // Opaque pointer to the Ghostty app instance.
    // Type will be `ghostty_app_t?` when GhosttyKit is imported.
    private var app: AnyObject?

    init() {
        initializeApp()
    }

    private func initializeApp() {
        // TODO: Uncomment when GhosttyKit.xcframework is available
        //
        // let config = ghostty_config_new()
        // ghostty_config_finalize(config)
        //
        // var runtimeConfig = ghostty_runtime_config_s(
        //     userdata: Unmanaged.passUnretained(self).toOpaque(),
        //     supports_selection_clipboard: false,
        //     wakeup_cb: { _ in },
        //     action_cb: { _, _, _ in false },
        //     read_clipboard_cb: { _, _, _ in false },
        //     confirm_read_clipboard_cb: { _, _, _, _ in },
        //     write_clipboard_cb: { _, _, _, _, _ in },
        //     close_surface_cb: { _, _ in }
        // )
        //
        // guard let app = ghostty_app_new(&runtimeConfig, config) else {
        //     readiness = .error
        //     return
        // }
        // self.app = app
        // readiness = .ready

        // Placeholder: mark as ready for UI development
        readiness = .ready
    }

    /// Tick the Ghostty event loop. Call from a display link or timer.
    func tick() {
        // TODO: ghostty_app_tick(app)
    }

    deinit {
        // TODO: ghostty_app_free(app)
    }
}

// MARK: - GhosttyKit Surface View (UIKit)

/// A UIView backed by CAMetalLayer that renders the Ghostty terminal surface.
///
/// This is the actual terminal rendering view. It manages:
/// - Metal GPU-accelerated rendering via CAMetalLayer
/// - Terminal surface lifecycle (ghostty_surface_t)
/// - Input forwarding (keyboard, mouse)
/// - Size/scale tracking for the terminal grid
final class GhosttySurface: UIView {
    // Published terminal state
    var title: String = "Terminal"
    var isHealthy: Bool = true
    var cellSize: CGSize = .zero

    // Opaque pointer to the Ghostty surface
    // Type will be `ghostty_surface_t?` when GhosttyKit is imported
    private var surface: AnyObject?

    /// Callback invoked when the terminal produces output data.
    /// Wire this to send data to the SSH channel.
    var onOutput: ((Data) -> Void)?

    /// Callback invoked when the terminal resizes (columns, rows).
    var onResize: ((Int, Int) -> Void)?

    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    private var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    init(app: GhosttyApp) {
        super.init(frame: .zero)
        setupMetalLayer()
        createSurface(app: app)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupMetalLayer() {
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.scale
        backgroundColor = .black
    }

    private func createSurface(app: GhosttyApp) {
        // TODO: Uncomment when GhosttyKit.xcframework is available
        //
        // guard let ghosttyApp = app.app else { return }
        //
        // var config = ghostty_surface_config_s()
        // config.userdata = Unmanaged.passUnretained(self).toOpaque()
        // config.platform_tag = GHOSTTY_PLATFORM_IOS
        // config.metal_layer = Unmanaged.passUnretained(metalLayer).toOpaque()
        //
        // surface = ghostty_surface_new(ghosttyApp, &config)
    }

    /// Write data received from SSH channel into the terminal.
    func writeToTerminal(_ data: Data) {
        // TODO: ghostty_surface_write(surface, data.withUnsafeBytes { $0.baseAddress }, data.count)
    }

    /// Notify the surface that its size changed.
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = metalLayer.contentsScale
        let width = UInt32(bounds.width * scale)
        let height = UInt32(bounds.height * scale)
        metalLayer.drawableSize = CGSize(width: CGFloat(width), height: CGFloat(height))

        // TODO: ghostty_surface_set_size(surface, width, height)
        // TODO: ghostty_surface_set_content_scale(surface, Float(scale), Float(scale))
        //
        // if let size = ghostty_surface_size(surface) {
        //     onResize?(Int(size.columns), Int(size.rows))
        // }
    }

    /// Forward focus state to the surface.
    func setFocused(_ focused: Bool) {
        // TODO: ghostty_surface_set_focus(surface, focused)
    }

    deinit {
        // TODO: ghostty_surface_free(surface)
    }
}

// MARK: - SwiftUI UIViewRepresentable Wrapper

/// SwiftUI wrapper for the GhosttyKit terminal surface.
///
/// Usage:
/// ```swift
/// GhosttyTerminalView(app: ghosttyApp, session: sshSession)
///     .ignoresSafeArea()
/// ```
struct GhosttyTerminalView: UIViewRepresentable {
    let app: GhosttyApp

    /// Called when the terminal produces output to send to SSH.
    var onOutput: ((Data) -> Void)?

    /// Called when terminal dimensions change (columns, rows).
    var onResize: ((Int, Int) -> Void)?

    /// Data to write into the terminal (from SSH channel).
    var incomingData: Data?

    func makeUIView(context: Context) -> GhosttySurface {
        let surface = GhosttySurface(app: app)
        surface.onOutput = onOutput
        surface.onResize = onResize
        return surface
    }

    func updateUIView(_ uiView: GhosttySurface, context: Context) {
        if let data = incomingData, !data.isEmpty {
            uiView.writeToTerminal(data)
        }
        uiView.onOutput = onOutput
        uiView.onResize = onResize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var displayLink: CADisplayLink?

        func startDisplayLink(for surface: GhosttySurface, app: GhosttyApp) {
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        }

        @objc private func tick() {
            // Drive the Ghostty event loop at display refresh rate
            // app.tick()
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
