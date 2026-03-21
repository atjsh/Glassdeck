import Foundation
import Observation

/// App-wide settings and preferences.
@Observable
public final class AppSettings {
    public var terminalConfig = TerminalConfiguration()
    public var autoReconnect = true
    public var reconnectDelay: TimeInterval = 3.0
    public var maxReconnectAttempts = 5
    public var hapticFeedback = true
    public var remoteTrackpadLastMode: RemoteControlMode = .cursor

    public init() {}
}
