import Foundation

/// App-wide settings and preferences.
@Observable
final class AppSettings {
    var terminalConfig = TerminalConfiguration()
    var autoReconnect = true
    var reconnectDelay: TimeInterval = 3.0
    var maxReconnectAttempts = 5
    var hapticFeedback = true
    var showAIButton = true
}
