import Foundation

/// A provider that can establish and manage interactive shell connections.
///
/// Abstracts the transport layer (SSH, local shell, etc.) so that the
/// session manager can work with any shell backend without coupling to
/// a specific implementation.
public protocol ShellSessionProvider: Sendable {
    /// Establish a connection to the target host.
    func connect(
        to profile: ConnectionProfile,
        password: String?
    ) async throws -> UUID

    /// Open an interactive shell on an established connection.
    func openShell(
        connectionID: UUID,
        configuration: ShellLaunchConfiguration
    ) async throws -> any InteractiveShell

    /// Disconnect an active connection.
    func disconnect(connectionID: UUID) async

    /// Remove a connection record entirely, releasing any remaining resources.
    func removeConnection(connectionID: UUID) async
}
