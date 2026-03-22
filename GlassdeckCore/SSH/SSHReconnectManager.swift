import Foundation

/// Handles automatic reconnection after SSH connection drops.
///
/// Implements exponential backoff with configurable max attempts.
/// Integrates with SessionManager to re-establish connections transparently.
/// Distinguishes transient failures (retry) from permanent failures (fail fast).
public actor SSHReconnectManager {
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]

    public struct Config: Sendable {
        public var enabled: Bool = true
        public var maxAttempts: Int = 5
        public var initialDelay: TimeInterval = 1.0
        public var maxDelay: TimeInterval = 30.0
        public var backoffMultiplier: Double = 2.0

        public init(
            enabled: Bool = true,
            maxAttempts: Int = 5,
            initialDelay: TimeInterval = 1.0,
            maxDelay: TimeInterval = 30.0,
            backoffMultiplier: Double = 2.0
        ) {
            self.enabled = enabled
            self.maxAttempts = maxAttempts
            self.initialDelay = initialDelay
            self.maxDelay = maxDelay
            self.backoffMultiplier = backoffMultiplier
        }
    }

    /// Classifies reconnection failures to determine retry strategy.
    public enum ReconnectError: Error, Sendable {
        /// Transient failures that may resolve on retry (e.g., network timeout).
        case transient(String)
        /// Permanent failures that won't resolve by retrying (e.g., auth failure, invalid host).
        case permanent(String)
    }

    private let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Start auto-reconnect for a disconnected session.
    ///
    /// - Parameters:
    ///   - sessionID: The session to reconnect.
    ///   - reconnect: Async closure that attempts reconnection.
    ///     Returns `.success` on success, `.failure(.transient)` to retry,
    ///     or `.failure(.permanent)` to stop immediately.
    ///   - onStatusChange: Called with status updates for UI display.
    public func startReconnecting(
        sessionID: UUID,
        reconnect: @escaping @Sendable () async -> Result<Void, ReconnectError>,
        onStatusChange: @escaping @Sendable (ReconnectStatus) -> Void
    ) {
        guard config.enabled else { return }

        // Cancel any existing reconnect for this session
        reconnectTasks[sessionID]?.cancel()

        reconnectTasks[sessionID] = Task {
            var attempt = 0
            var delay = config.initialDelay

            while attempt < config.maxAttempts && !Task.isCancelled {
                attempt += 1
                onStatusChange(.attempting(attempt: attempt, maxAttempts: config.maxAttempts))

                // Wait before attempting
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }

                // Try reconnecting
                switch await reconnect() {
                case .success:
                    onStatusChange(.reconnected)
                    self.finishReconnecting(sessionID: sessionID)
                    return
                case .failure(.permanent(let reason)):
                    onStatusChange(.permanentFailure(reason: reason))
                    self.finishReconnecting(sessionID: sessionID)
                    return
                case .failure(.transient):
                    break // Continue retrying
                }

                // Exponential backoff
                delay = min(delay * config.backoffMultiplier, config.maxDelay)
            }

            if !Task.isCancelled {
                onStatusChange(.gaveUp(attempts: attempt))
            }
            self.finishReconnecting(sessionID: sessionID)
        }
    }

    /// Cancel reconnection attempts for a session.
    public func cancelReconnecting(sessionID: UUID) {
        reconnectTasks[sessionID]?.cancel()
        reconnectTasks.removeValue(forKey: sessionID)
    }

    /// Cancel all reconnection attempts.
    public func cancelAll() {
        for task in reconnectTasks.values {
            task.cancel()
        }
        reconnectTasks.removeAll()
    }

    private func finishReconnecting(sessionID: UUID) {
        reconnectTasks.removeValue(forKey: sessionID)
    }

    public enum ReconnectStatus: Sendable, Equatable {
        case attempting(attempt: Int, maxAttempts: Int)
        case reconnected
        case gaveUp(attempts: Int)
        case permanentFailure(reason: String)

        public var label: String {
            switch self {
            case .attempting(let attempt, let max):
                return "Reconnecting (\(attempt)/\(max))…"
            case .reconnected:
                return "Reconnected"
            case .gaveUp(let attempts):
                return "Failed after \(attempts) attempts"
            case .permanentFailure(let reason):
                return reason
            }
        }
    }
}
