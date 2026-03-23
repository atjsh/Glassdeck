#if canImport(UIKit)
import Foundation
import GhosttyKit
import UIKit
import os

/// Singleton that initializes the GhosttyKit runtime once for the app lifetime.
///
/// Provides the `ghostty_app_t` required to create surfaces.
/// Must be accessed on the main actor.
@MainActor
final class GhosttyKitApp {
    static let shared = GhosttyKitApp()

    private(set) var app: ghostty_app_t?

    private static let logger = Logger(subsystem: "com.glassdeck", category: "GhosttyKitApp")

    private init() {
        // Initialize the GhosttyKit runtime.
        if ghostty_init(0, nil) != GHOSTTY_SUCCESS {
            Self.logger.critical("ghostty_init failed")
            return
        }

        // Create a minimal runtime config with required callbacks.
        var runtimeCfg = ghostty_runtime_config_s()
        runtimeCfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeCfg.supports_selection_clipboard = false
        runtimeCfg.wakeup_cb = { userdata in
            DispatchQueue.main.async {
                guard let userdata else { return }
                let app = Unmanaged<GhosttyKitApp>.fromOpaque(userdata).takeUnretainedValue()
                if let ghosttyApp = app.app {
                    ghostty_app_tick(ghosttyApp)
                }
            }
        }
        runtimeCfg.action_cb = { ghosttyApp, target, action in
            GhosttyKitApp.handleAction(ghosttyApp, target: target, action: action)
        }
        runtimeCfg.read_clipboard_cb = { _, _, _ in
            false
        }
        runtimeCfg.confirm_read_clipboard_cb = nil
        runtimeCfg.write_clipboard_cb = { _, _, _, _, _ in }
        runtimeCfg.close_surface_cb = nil

        let config = ghostty_config_new()
        guard let config else {
            Self.logger.critical("ghostty_config_new failed")
            return
        }
        ghostty_config_finalize(config)
        defer { ghostty_config_free(config) }

        guard let app = ghostty_app_new(&runtimeCfg, config) else {
            Self.logger.critical("ghostty_app_new failed")
            return
        }
        self.app = app
    }

    // MARK: - Action Handling

    private static func handleAction(
        _ ghosttyApp: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
            let surface = target.target.surface
            guard let titlePtr = action.action.set_title.title else { return false }
            let title = String(cString: titlePtr)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .ghosttyKitSurfaceTitleChanged,
                    object: surface,
                    userInfo: ["title": title]
                )
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .ghosttyKitBellRung,
                    object: target.tag == GHOSTTY_TARGET_SURFACE ? target.target.surface : nil
                )
            }
            return true

        default:
            return false
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let ghosttyKitSurfaceTitleChanged = Notification.Name("ghosttyKitSurfaceTitleChanged")
    static let ghosttyKitBellRung = Notification.Name("ghosttyKitBellRung")
}
#endif
