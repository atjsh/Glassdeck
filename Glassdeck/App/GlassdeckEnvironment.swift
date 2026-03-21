#if canImport(UIKit)
import GlassdeckCore
import Foundation

@MainActor
enum GlassdeckEnvironment {
    static let appSettings = AppSettings()
    static let sessionManager = SessionManager(appSettings: appSettings)
    static let connectionStore = ConnectionStore()
}
#endif
