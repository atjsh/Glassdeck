import Foundation
@testable import GlassdeckCore
import SSHClient
import XCTest

final class SFTPManagerTests: XCTestCase {
    func testConnectBrowseDownloadUploadDeleteAndDisconnect() async throws {
        let session = FakeSFTPClientSession(
            listings: [
                ".": [
                    SFTPBrowserEntry(name: ".", path: ".", isDirectory: true),
                    SFTPBrowserEntry(name: "..", path: "..", isDirectory: true),
                    SFTPBrowserEntry(
                        name: "bin",
                        path: "bin",
                        longName: "drwxr-xr-x 2 user user 4096 Jan 1 00:00 bin",
                        attributes: SFTPFileAttributes(permissions: 0o040755),
                        isDirectory: true
                    ),
                    SFTPBrowserEntry(
                        name: "notes.txt",
                        path: "notes.txt",
                        longName: "-rw-r--r-- 1 user user 12 Jan 1 00:00 notes.txt",
                        attributes: SFTPFileAttributes(size: 12, permissions: 0o100644)
                    )
                ]
            ],
            fileData: [
                "notes.txt": Data("hello world".utf8)
            ]
        )
        let provider = FakeSFTPClientSessionProvider(session: session)
        let manager = SFTPManager(sessionProvider: provider)
        let profile = ConnectionProfile(name: "Dev", host: "example.com", username: "user")

        let connectionID = try await manager.connect(to: profile, password: "secret")
        let connectCount = await provider.connectCount
        let receivedPasswords = await provider.receivedPasswords
        let connectedStatus = await manager.status(for: connectionID)
        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(receivedPasswords, ["secret"])
        XCTAssertEqual(connectedStatus, SFTPConnectionStatus.connected)

        let root = try await manager.browse(connectionID: connectionID, at: ".")
        XCTAssertEqual(root.entries.map(\.name), ["bin", "notes.txt"])

        let blob = try await manager.download(connectionID: connectionID, at: "notes.txt")
        XCTAssertEqual(blob, SFTPFileBlob(path: "notes.txt", data: Data("hello world".utf8)))

        try await manager.upload(
            connectionID: connectionID,
            data: Data("uploaded".utf8),
            to: "upload.txt"
        )
        let writes = await session.writes
        XCTAssertEqual(writes["upload.txt"], Data("uploaded".utf8))

        let preview = try await manager.previewText(
            connectionID: connectionID,
            at: "notes.txt",
            maxBytes: 5
        )
        XCTAssertEqual(preview, SFTPTextPreview(path: "notes.txt", text: "hello", isTruncated: true))

        try await manager.delete(connectionID: connectionID, at: "notes.txt", isDirectory: false)
        let removedItems = await session.removedItems
        XCTAssertEqual(removedItems.count, 1)
        XCTAssertEqual(removedItems.first?.0, "notes.txt")
        XCTAssertEqual(removedItems.first?.1, false)

        await manager.disconnect(id: connectionID)
        let disconnectedStatus = await manager.status(for: connectionID)
        let didClose = await session.didClose
        XCTAssertEqual(disconnectedStatus, SFTPConnectionStatus.disconnected)
        XCTAssertTrue(didClose)
    }

    func testBrowseFailsWhenDisconnected() async throws {
        let manager = SFTPManager(
            sessionProvider: FakeSFTPClientSessionProvider(session: FakeSFTPClientSession())
        )
        let profile = ConnectionProfile(name: "Dev", host: "example.com", username: "user")

        let connectionID = try await manager.connect(to: profile, password: nil)
        await manager.disconnect(id: connectionID)

        await XCTAssertThrowsErrorAsync {
            _ = try await manager.browse(connectionID: connectionID, at: ".")
        } verify: { error in
            XCTAssertEqual(error as? SFTPManagerError, .notConnected)
        }
    }

    func testOperationFailureMarksConnectionFailed() async throws {
        let session = FakeSFTPClientSession(
            listings: [:],
            fileData: [:],
            readError: TestSFTPError.readFailed
        )
        let manager = SFTPManager(
            sessionProvider: FakeSFTPClientSessionProvider(session: session)
        )
        let profile = ConnectionProfile(name: "Dev", host: "example.com", username: "user")
        let connectionID = try await manager.connect(to: profile, password: nil)

        await XCTAssertThrowsErrorAsync {
            _ = try await manager.download(connectionID: connectionID, at: "missing.txt")
        } verify: { error in
            XCTAssertEqual(error as? TestSFTPError, .readFailed)
        }

        let status = await manager.status(for: connectionID)
        XCTAssertEqual(status, .failed(TestSFTPError.readFailed.localizedDescription))
    }
}

private actor FakeSFTPClientSession: SFTPClientSession {
    private let listings: [String: [SFTPBrowserEntry]]
    private let readError: Error?
    private let writeError: Error?
    private let deleteError: Error?
    private(set) var fileData: [String: Data]
    private(set) var writes: [String: Data] = [:]
    private(set) var removedItems: [(String, Bool)] = []
    private(set) var didClose = false

    init(
        listings: [String: [SFTPBrowserEntry]] = [:],
        fileData: [String: Data] = [:],
        readError: Error? = nil,
        writeError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.listings = listings
        self.fileData = fileData
        self.readError = readError
        self.writeError = writeError
        self.deleteError = deleteError
    }

    func listDirectory(at path: SFTPFilePath) async throws -> [SFTPBrowserEntry] {
        listings[path.string] ?? []
    }

    func readFile(at path: SFTPFilePath, maxBytes: Int?) async throws -> Data {
        if let readError {
            throw readError
        }

        let data = fileData[path.string] ?? Data()
        if let maxBytes {
            return Data(data.prefix(maxBytes))
        }
        return data
    }

    func writeFile(_ data: Data, to path: SFTPFilePath) async throws {
        if let writeError {
            throw writeError
        }

        writes[path.string] = data
        fileData[path.string] = data
    }

    func removeItem(at path: SFTPFilePath, isDirectory: Bool) async throws {
        if let deleteError {
            throw deleteError
        }

        removedItems.append((path.string, isDirectory))
        fileData.removeValue(forKey: path.string)
    }

    func close() async {
        didClose = true
    }
}

private actor FakeSFTPClientSessionProvider: SFTPClientSessionProviding {
    let session: FakeSFTPClientSession
    private(set) var connectCount = 0
    private(set) var receivedPasswords: [String?] = []

    init(session: FakeSFTPClientSession) {
        self.session = session
    }

    func connect(
        to profile: ConnectionProfile,
        password: String?
    ) async throws -> any SFTPClientSession {
        connectCount += 1
        receivedPasswords.append(password)
        return session
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: @escaping @Sendable () async throws -> Void,
        verify: @escaping (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}

private enum TestSFTPError: Error, LocalizedError, Equatable {
    case readFailed

    var errorDescription: String? {
        switch self {
        case .readFailed:
            return "Read failed"
        }
    }
}
