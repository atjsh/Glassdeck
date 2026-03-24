import Foundation
import GhosttyKit

/// TerminalIO adapter for GhosttyKit surfaces.
///
/// Thread-safe: the write callback is invoked from GhosttyKit's IO thread,
/// NOT the main thread. We guard the output handler with an NSLock and
/// never touch @MainActor state from the callback.
public final class GhosttyKitSurfaceIO: TerminalIO, @unchecked Sendable {
    private static let debugTerminalInput = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private let lock = NSLock()
    private var _outputHandler: (@Sendable (Data) -> Void)?

    /// The ghostty surface pointer, set once via `configure(surface:)`.
    private var surfacePtr: ghostty_surface_t?

    public init() {}

    /// Binds this IO adapter to a ghostty surface.
    /// Must be called exactly once, from the main thread, before any I/O begins.
    public func configure(surface: ghostty_surface_t) {
        self.surfacePtr = surface

        ghostty_surface_set_write_callback(
            surface,
            { userdata, ptr, len in
                guard let userdata else { return }
                guard let ptr else { return }
                let io = Unmanaged<GhosttyKitSurfaceIO>.fromOpaque(userdata)
                    .takeUnretainedValue()
                let data = Data(bytes: ptr, count: Int(len))
                io.debugLog("callback len=\(data.count) data=\(GhosttyKitSurfaceIO.debugDescription(for: data))")
                io.lock.lock()
                let handler = io._outputHandler
                io.lock.unlock()
                handler?(data)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Detach from the surface, clearing the callback.
    public func detach() {
        guard let surface = surfacePtr else { return }
        ghostty_surface_set_write_callback(surface, nil, nil)
        surfacePtr = nil
    }

    // MARK: - TerminalIO

    public func setOutputHandler(_ handler: (@Sendable (Data) -> Void)?) async {
        lock.withLock {
            _outputHandler = handler
        }
    }

    /// Feed SSH data into the terminal for rendering.
    public func write(_ data: Data) async {
        guard let surface = surfacePtr else { return }
        debugLog("process_output len=\(data.count) data=\(Self.debugDescription(for: data))")
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            ghostty_surface_process_output(
                surface,
                ptr.assumingMemoryBound(to: CChar.self),
                UInt(buf.count)
            )
        }
    }

    public func emitInput(_ data: Data) {
        debugLog("emitInput len=\(data.count) data=\(Self.debugDescription(for: data))")
        lock.lock()
        let handler = _outputHandler
        lock.unlock()
        handler?(data)
    }

    private func debugLog(_ message: String) {
        guard GhosttyKitSurfaceIO.debugTerminalInput else { return }
        NSLog("GhosttyKitSurfaceIO %@", message)
    }

    private static func debugDescription(for data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
