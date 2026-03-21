#if canImport(UIKit)
import GlassdeckCore
import Foundation

@MainActor
enum GlassdeckEnvironment {
    static let sessionManager = SessionManager()
    static let connectionStore = ConnectionStore()
    static let appSettings = AppSettings()
}
#endif
