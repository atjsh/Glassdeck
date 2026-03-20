import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SSHClient

/// Manages SSH connection lifecycle with Swift actor isolation.
///
/// Uses swift-ssh-client for high-level connection management and
/// SwiftNIO SSH for the underlying transport. Each connection is
/// tracked by UUID and supports shell request and disconnect.
actor SSHConnectionManager {
    private var connections: [UUID: ManagedConnection] = [:]
    private let eventLoopGroup: EventLoopGroup

    struct ManagedConnection {
        let id: UUID
        let profile: ConnectionProfile
        let connection: SSHConnection
        var shell: SSHShell?
        var status: ConnectionStatus
    }

    enum ConnectionStatus: Sendable {
        case connecting
        case authenticating
        case connected
        case disconnecting
        case disconnected
        case failed(String)
    }

    init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    /// Establish an SSH connection with authentication.
    ///
    /// - Parameters:
    ///   - profile: Connection details (host, port, username, auth method).
    ///   - password: Password for password auth (ignored for key auth).
    /// - Returns: Connection UUID for referencing this connection.
    func connect(to profile: ConnectionProfile, password: String? = nil) async throws -> UUID {
        let id = UUID()
        let authMethod = try buildAuthMethod(for: profile, password: password)

        let sshConnection = SSHConnection(
            host: profile.host,
            port: UInt16(profile.port),
            authentication: SSHAuthentication(
                username: profile.username,
                method: authMethod,
                hostKeyValidation: .acceptAll()
            ),
            defaultTimeout: 15.0
        )

        connections[id] = ManagedConnection(
            id: id,
            profile: profile,
            connection: sshConnection,
            shell: nil,
            status: .connecting
        )

        // Monitor connection state
        sshConnection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateUpdate(id: id, state: state) }
        }

        // Connect and authenticate
        do {
            connections[id]?.status = .authenticating
            try await sshConnection.start()
            connections[id]?.status = .connected
        } catch {
            connections[id]?.status = .failed(error.localizedDescription)
            throw error
        }

        return id
    }

    /// Open a PTY shell on an existing connection.
    ///
    /// Requests a shell channel with TERM=xterm-256color.
    func openShell(connectionID: UUID) async throws -> SSHShell {
        guard let managed = connections[connectionID],
              case .connected = managed.status else {
            throw SSHError.notConnected
        }

        let shell = try await managed.connection.requestShell()
        connections[connectionID]?.shell = shell
        return shell
    }

    /// Disconnect an active SSH session.
    func disconnect(id: UUID) async {
        guard var managed = connections[id] else { return }
        managed.status = .disconnecting

        if let shell = managed.shell {
            shell.close { _ in }
        }

        managed.connection.cancel { }
        managed.status = .disconnected
        connections[id] = managed
    }

    /// Get current status of a connection.
    func status(for id: UUID) -> ConnectionStatus? {
        connections[id]?.status
    }

    /// Remove a connection record.
    func remove(id: UUID) {
        connections.removeValue(forKey: id)
    }

    // MARK: - Private

    private func buildAuthMethod(
        for profile: ConnectionProfile,
        password: String?
    ) throws -> SSHAuthentication.Method {
        switch profile.authMethod {
        case .password:
            return SSHAuthenticator.passwordMethod(password ?? "")
        case .sshKey:
            if let keyID = profile.sshKeyID {
                return try SSHAuthenticator.keyMethod(keyID: keyID)
            }
            // Fallback to password if no key is configured
            return SSHAuthenticator.passwordMethod(password ?? "")
        }
    }

    private func handleStateUpdate(id: UUID, state: SSHConnection.State) {
        switch state {
        case .idle:
            connections[id]?.status = .disconnected
        case .ready:
            connections[id]?.status = .connected
        case .failed:
            connections[id]?.status = .failed("Connection failed")
        @unknown default:
            break
        }
    }

    enum SSHError: Error, LocalizedError {
        case notConnected
        case authFailed(String)
        case shellFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to SSH server"
            case .authFailed(let msg): return "Authentication failed: \(msg)"
            case .shellFailed(let msg): return "Failed to open shell: \(msg)"
            }
        }
    }
}

