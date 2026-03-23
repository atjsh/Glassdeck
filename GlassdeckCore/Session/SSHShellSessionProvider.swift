import Foundation

/// SSH-backed implementation of ``ShellSessionProvider``.
///
/// Delegates to ``SSHConnectionManager`` for the actual SSH transport,
/// authentication, and shell creation.
public final class SSHShellSessionProvider: ShellSessionProvider {
    private let connectionManager: SSHConnectionManager

    public init(connectionManager: SSHConnectionManager = SSHConnectionManager()) {
        self.connectionManager = connectionManager
    }

    public func connect(
        to profile: ConnectionProfile,
        password: String?
    ) async throws -> UUID {
        try await connectionManager.connect(to: profile, password: password)
    }

    public func openShell(
        connectionID: UUID,
        configuration: ShellLaunchConfiguration
    ) async throws -> any InteractiveShell {
        try await connectionManager.openShell(
            connectionID: connectionID,
            configuration: configuration
        )
    }

    public func disconnect(connectionID: UUID) async {
        await connectionManager.disconnect(id: connectionID)
    }

    public func removeConnection(connectionID: UUID) async {
        connectionManager.remove(id: connectionID)
    }
}
