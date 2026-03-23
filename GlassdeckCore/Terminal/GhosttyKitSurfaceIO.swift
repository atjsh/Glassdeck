#if canImport(GhosttyKit)
import Foundation
import GhosttyKit

/// TerminalIO adapter for GhosttyKit surfaces.
///
/// Thread-safe: the write callback is invoked from GhosttyKit's IO thread,
/// NOT the main thread. We guard the output handler with an NSLock and
/// never touch @MainActor state from the callback.
public final class GhosttyKitSurfaceIO: TerminalIO, @unchecked Sendable {
    private let lock = NSLock()
    private var _outputHandler: (@Sendable (Data) -> Void)?

    /// The ghostty surface pointer, set once via `configure(surface:)`.
    private var surfacePtr: ghostty_surface_t?

    public init() {}

    /// Binds this IO adapter to a ghostty surface.
    /// Must be called exactly once, from the main thread, before any I/O begins.
    func configure(surface: ghostty_surface_t) {
        self.surfacePtr = surface

        ghostty_surface_set_write_callback(
            surface,
            { userdata, ptr, len in
                guard let userdata else { return }
                guard let ptr else { return }
                let io = Unmanaged<GhosttyKitSurfaceIO>.fromOpaque(userdata)
                    .takeUnretainedValue()
                let data = Data(bytes: ptr, count: Int(len))
                io.lock.lock()
                let handler = io._outputHandler
                io.lock.unlock()
                handler?(data)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Detach from the surface, clearing the callback.
    func detach() {
        guard let surface = surfacePtr else { return }
        ghostty_surface_set_write_callback(surface, nil, nil)
        surfacePtr = nil
    }

    // MARK: - TerminalIO

    public func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) async {
        lock.lock()
        _outputHandler = handler
        lock.unlock()
    }

    /// Feed SSH data into the terminal for rendering.
    public func write(_ data: Data) async {
        guard let surface = surfacePtr else { return }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            ghostty_surface_process_output(
                surface,
                ptr.assumingMemoryBound(to: CChar.self),
                buf.count
            )
        }
    }
}
#endif
