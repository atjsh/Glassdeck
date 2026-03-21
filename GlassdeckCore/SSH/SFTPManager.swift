import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SSHClient

public struct SFTPBrowserEntry: Identifiable, Sendable {
    public let name: String
    public let path: String
    public let longName: String
    public let attributes: SFTPFileAttributes
    public let isDirectory: Bool

    public var id: String { path }

    public var fileSize: UInt64? {
        attributes.size
    }

    public var modificationDate: Date? {
        attributes.accessModificationTime?.modificationTime
    }

    public init(
        name: String,
        path: String,
        longName: String = "",
        attributes: SFTPFileAttributes = .none,
        isDirectory: Bool = false
    ) {
        self.name = name
        self.path = path
        self.longName = longName
        self.attributes = attributes
        self.isDirectory = isDirectory
    }
}

public struct SFTPDirectoryListing: Sendable {
    public let path: String
    public let entries: [SFTPBrowserEntry]

    public init(path: String, entries: [SFTPBrowserEntry]) {
        self.path = path
        self.entries = entries
    }
}

public struct SFTPFileBlob: Sendable, Equatable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

public struct SFTPTextPreview: Sendable, Equatable {
    public let path: String
    public let text: String
    public let isTruncated: Bool

    public init(path: String, text: String, isTruncated: Bool) {
        self.path = path
        self.text = text
        self.isTruncated = isTruncated
    }
}

public enum SFTPManagerError: Error, LocalizedError, Equatable {
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to an SFTP session"
        }
    }
}

public enum SFTPConnectionStatus: Sendable, Equatable {
    case connecting
    case authenticating
    case connected
    case disconnecting
    case disconnected
    case failed(String)
}

public protocol SFTPClientSession: Sendable {
    func listDirectory(at path: SFTPFilePath) async throws -> [SFTPBrowserEntry]
    func readFile(at path: SFTPFilePath, maxBytes: Int?) async throws -> Data
    func writeFile(_ data: Data, to path: SFTPFilePath) async throws
    func removeItem(at path: SFTPFilePath, isDirectory: Bool) async throws
    func close() async
}

public protocol SFTPClientSessionProviding: Sendable {
    func connect(
        to profile: ConnectionProfile,
        password: String?
    ) async throws -> any SFTPClientSession
}

public protocol SFTPManaging: Sendable {
    func connect(
        to profile: ConnectionProfile,
        password: String?
    ) async throws -> UUID

    func browse(
        connectionID: UUID,
        at path: String
    ) async throws -> SFTPDirectoryListing

    func download(
        connectionID: UUID,
        at path: String
    ) async throws -> SFTPFileBlob

    func upload(
        connectionID: UUID,
        data: Data,
        to path: String
    ) async throws

    func delete(
        connectionID: UUID,
        at path: String,
        isDirectory: Bool
    ) async throws

    func previewText(
        connectionID: UUID,
        at path: String,
        maxBytes: Int
    ) async throws -> SFTPTextPreview

    func disconnect(id: UUID) async
    func status(for id: UUID) async -> SFTPConnectionStatus?

    func remove(id: UUID) async
}

public actor SFTPManager: SFTPManaging {
    private struct ManagedSession {
        let id: UUID
        let profile: ConnectionProfile
        var session: (any SFTPClientSession)?
        var status: SFTPConnectionStatus
    }

    private var sessions: [UUID: ManagedSession] = [:]
    private let sessionProvider: any SFTPClientSessionProviding

    public init(sessionProvider: any SFTPClientSessionProviding = LiveSFTPClientSessionProvider()) {
        self.sessionProvider = sessionProvider
    }

    public func connect(
        to profile: ConnectionProfile,
        password: String? = nil
    ) async throws -> UUID {
        let id = UUID()
        sessions[id] = ManagedSession(
            id: id,
            profile: profile,
            session: nil,
            status: .connecting
        )

        do {
            sessions[id]?.status = .authenticating
            let session = try await sessionProvider.connect(to: profile, password: password)
            sessions[id]?.session = session
            sessions[id]?.status = .connected
            return id
        } catch {
            sessions[id]?.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func browse(
        connectionID: UUID,
        at path: String = "."
    ) async throws -> SFTPDirectoryListing {
        let session = try connectedSession(for: connectionID)

        do {
            let entries = try await session.listDirectory(at: SFTPFilePath(path))
            let filtered = entries
                .filter { $0.name != "." && $0.name != ".." }
                .sorted(by: Self.sortEntries)
            return SFTPDirectoryListing(path: path, entries: filtered)
        } catch {
            sessions[connectionID]?.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func download(
        connectionID: UUID,
        at path: String
    ) async throws -> SFTPFileBlob {
        let session = try connectedSession(for: connectionID)

        do {
            let data = try await session.readFile(at: SFTPFilePath(path), maxBytes: nil)
            return SFTPFileBlob(path: path, data: data)
        } catch {
            sessions[connectionID]?.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func upload(
        connectionID: UUID,
        data: Data,
        to path: String
    ) async throws {
        let session = try connectedSession(for: connectionID)

        do {
            try await session.writeFile(data, to: SFTPFilePath(path))
        } catch {
            sessions[connectionID]?.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func delete(
        connectionID: UUID,
        at path: String,
        isDirectory: Bool
    ) async throws {
        let session = try connectedSession(for: connectionID)

        do {
            try await session.removeItem(at: SFTPFilePath(path), isDirectory: isDirectory)
        } catch {
            sessions[connectionID]?.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func previewText(
        connectionID: UUID,
        at path: String,
        maxBytes: Int = 8_192
    ) async throws -> SFTPTextPreview {
        let session = try connectedSession(for: connectionID)
        let requestedLength = max(1, maxBytes + 1)

        do {
            let data = try await session.readFile(at: SFTPFilePath(path), maxBytes: requestedLength)
            let previewData = data.prefix(maxBytes)
            return SFTPTextPreview(
                path: path,
                text: String(data: Data(previewData), encoding: .utf8)
                    ?? "Preview unavailable for non-UTF-8 content.",
                isTruncated: data.count > maxBytes
            )
        } catch {
            sessions[connectionID]?.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func disconnect(id: UUID) async {
        guard var managed = sessions[id] else { return }
        managed.status = .disconnecting

        if let session = managed.session {
            await session.close()
        }

        managed.status = .disconnected
        managed.session = nil
        sessions[id] = managed
    }

    public func status(for id: UUID) async -> SFTPConnectionStatus? {
        sessions[id]?.status
    }

    public func remove(id: UUID) async {
        sessions.removeValue(forKey: id)
    }

    private static func sortEntries(_ lhs: SFTPBrowserEntry, _ rhs: SFTPBrowserEntry) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func connectedSession(for connectionID: UUID) throws -> any SFTPClientSession {
        guard let managed = sessions[connectionID],
              case .connected = managed.status,
              let session = managed.session else {
            throw SFTPManagerError.notConnected
        }
        return session
    }
}

public struct LiveSFTPClientSessionProvider: SFTPClientSessionProviding {
    public init() {}

    public func connect(
        to profile: ConnectionProfile,
        password: String?
    ) async throws -> any SFTPClientSession {
        let connection = SSHConnection(
            host: profile.host,
            port: UInt16(profile.port),
            authentication: SSHAuthentication(
                username: profile.username,
                method: try Self.buildAuthMethod(for: profile, password: password),
                hostKeyValidation: .acceptAll()
            ),
            defaultTimeout: 15.0
        )

        do {
            try await connection.start()
            let client = try await connection.requestSFTPClient()
            return LiveSFTPClientSession(connection: connection, client: client)
        } catch {
            await connection.cancel()
            throw error
        }
    }

    private static func buildAuthMethod(
        for profile: ConnectionProfile,
        password: String?
    ) throws -> SSHAuthentication.Method {
        switch profile.authMethod {
        case .password:
            return SSHAuthenticator.passwordMethod(password ?? "")
        case .sshKey:
            if let keyID = profile.sshKeyID {
                return try SSHAuthenticator.keyMethod(
                    username: profile.username,
                    keyID: keyID
                )
            }
            return SSHAuthenticator.passwordMethod(password ?? "")
        }
    }
}

private final class LiveSFTPClientSession: SFTPClientSession, @unchecked Sendable {
    private let connection: SSHConnection
    private let client: SFTPClient
    private let callbackQueue = DispatchQueue(label: "glassdeck.sftp.session")

    init(connection: SSHConnection, client: SFTPClient) {
        self.connection = connection
        self.client = client
    }

    func listDirectory(at path: SFTPFilePath) async throws -> [SFTPBrowserEntry] {
        let components = try await client.listDirectory(at: path)
        return components.map { component in
            SFTPBrowserEntry(
                name: component.filename.string,
                path: Self.join(remotePath: path.string, child: component.filename.string),
                longName: component.longname,
                attributes: component.attributes,
                isDirectory: Self.isDirectory(attributes: component.attributes)
            )
        }
    }

    func readFile(at path: SFTPFilePath, maxBytes: Int?) async throws -> Data {
        let file = try await openFile(
            at: path,
            flags: [.read]
        )
        do {
            let data = try await readAll(
                file: file,
                maxBytes: maxBytes
            )
            try await close(file: file)
            return data
        } catch {
            await closeIgnoringErrors(file: file)
            throw error
        }
    }

    func writeFile(_ data: Data, to path: SFTPFilePath) async throws {
        let file = try await openFile(
            at: path,
            flags: [.write, .create, .truncate]
        )
        do {
            if !data.isEmpty {
                try await write(data: data, to: file)
            }
            try await close(file: file)
        } catch {
            await closeIgnoringErrors(file: file)
            throw error
        }
    }

    func removeItem(at path: SFTPFilePath, isDirectory: Bool) async throws {
        if isDirectory {
            try await client.removeDirectory(at: path)
        } else {
            try await client.removeFile(at: path)
        }
    }

    func close() async {
        await client.close()
        await connection.cancel()
    }

    private func openFile(
        at path: SFTPFilePath,
        flags: SFTPOpenFileFlags,
        attributes: SFTPFileAttributes = .none
    ) async throws -> SFTPFile {
        try await withCheckedThrowingContinuation { continuation in
            client.openFile(
                at: path,
                flags: flags,
                attributes: attributes,
                updateQueue: callbackQueue
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func read(file: SFTPFile, from offset: UInt64, length: UInt32) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            file.read(from: offset, length: length) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func readAll(file: SFTPFile, maxBytes: Int?) async throws -> Data {
        let chunkSize = 32_000
        var data = Data()
        var offset: UInt64 = 0

        while true {
            let requestLength: UInt32
            if let maxBytes {
                let remaining = max(0, maxBytes - data.count)
                if remaining == 0 {
                    break
                }
                requestLength = UInt32(clamping: min(chunkSize, remaining))
            } else {
                requestLength = UInt32(chunkSize)
            }

            let chunk = try await read(file: file, from: offset, length: requestLength)
            if chunk.isEmpty {
                break
            }

            data.append(chunk)
            offset += UInt64(chunk.count)

            if let maxBytes, data.count >= maxBytes {
                break
            }

            if chunk.count < Int(requestLength) {
                break
            }
        }

        return data
    }

    private func write(data: Data, to file: SFTPFile) async throws {
        try await withCheckedThrowingContinuation { continuation in
            file.write(data) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func close(file: SFTPFile) async throws {
        try await withCheckedThrowingContinuation { continuation in
            file.close { result in
                continuation.resume(with: result)
            }
        }
    }

    private func closeIgnoringErrors(file: SFTPFile) async {
        do {
            try await close(file: file)
        } catch {
            return
        }
    }

    private static func join(remotePath: String, child: String) -> String {
        if remotePath.isEmpty || remotePath == "." {
            return child
        }

        if remotePath == "/" {
            return "/\(child)"
        }

        if remotePath.hasSuffix("/") {
            return remotePath + child
        }

        return "\(remotePath)/\(child)"
    }

    private static func isDirectory(attributes: SFTPFileAttributes) -> Bool {
        guard let permissions = attributes.permissions else { return false }
        return (permissions & 0o170000) == 0o040000
    }
}
