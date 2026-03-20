import Foundation

/// Handles automatic reconnection after SSH connection drops.
///
/// Implements exponential backoff with configurable max attempts.
/// Integrates with SessionManager to re-establish connections transparently.
actor SSHReconnectManager {
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]

    struct Config: Sendable {
        var enabled: Bool = true
        var maxAttempts: Int = 5
        var initialDelay: TimeInterval = 1.0
        var maxDelay: TimeInterval = 30.0
        var backoffMultiplier: Double = 2.0
    }

    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    /// Start auto-reconnect for a disconnected session.
    ///
    /// - Parameters:
    ///   - sessionID: The session to reconnect.
    ///   - reconnect: Async closure that attempts reconnection. Returns true on success.
    ///   - onStatusChange: Called with status updates for UI display.
    func startReconnecting(
        sessionID: UUID,
        reconnect: @escaping @Sendable () async -> Bool,
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
                let success = await reconnect()
                if success {
                    onStatusChange(.reconnected)
                    return
                }

                // Exponential backoff
                delay = min(delay * config.backoffMultiplier, config.maxDelay)
            }

            if !Task.isCancelled {
                onStatusChange(.gaveUp(attempts: attempt))
            }
        }
    }

    /// Cancel reconnection attempts for a session.
    func cancelReconnecting(sessionID: UUID) {
        reconnectTasks[sessionID]?.cancel()
        reconnectTasks.removeValue(forKey: sessionID)
    }

    /// Cancel all reconnection attempts.
    func cancelAll() {
        for task in reconnectTasks.values {
            task.cancel()
        }
        reconnectTasks.removeAll()
    }

    enum ReconnectStatus: Sendable {
        case attempting(attempt: Int, maxAttempts: Int)
        case reconnected
        case gaveUp(attempts: Int)

        var label: String {
            switch self {
            case .attempting(let attempt, let max):
                return "Reconnecting (\(attempt)/\(max))…"
            case .reconnected:
                return "Reconnected"
            case .gaveUp(let attempts):
                return "Failed after \(attempts) attempts"
            }
        }
    }
}
