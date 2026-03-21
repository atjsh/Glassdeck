
import Foundation
import SSHClient
import XCTest

class SSHAsyncTests: XCTestCase {
    var sshServer: SSHServer!
    var connection: SSHConnection!

    override func setUp() {
        sshServer = DockerSSHServer()
        connection = SSHConnection(
            host: sshServer.host,
            port: sshServer.port,
            authentication: sshServer.credentials
        )
    }

    // MARK: - Connection

    func testCommandExecution() async throws {
        try await connection.start()
        await connection.cancel()
    }

    func testCommandStreaming() async throws {
        try await connection.start()
        let stream = try await connection.stream("yes \"long text\" | head -n 10000\n")
        var standard = Data()
        for try await chunk in stream {
            switch chunk {
            case .chunk(let output):
                standard.append(output.data)
            case .status:
                break
            }
        }
        XCTAssertEqual(standard.count, 100_000)
        await connection.cancel()
    }

    func testShell() async throws {
        try await connection.start()
        let shell = try await connection.requestShell()
        let reader = ShellActor()
        Task {
            do {
                for try await data in shell.data {
                    await reader.addData(data)
                }
                await reader.end()
            } catch {
                await reader.fail()
            }
        }
        try await shell.write("echo Hello\n".data(using: .utf8)!)
        wait(timeout: 0.5)
        try await shell.close()
        wait(timeout: 0.5)
        let hasFailed = await reader.hasFailed
        let isEnded = await reader.isEnded
        let result = await reader.result
        XCTAssertFalse(hasFailed)
        XCTAssertTrue(isEnded)
        XCTAssertEqual(result, "Hello\n".data(using: .utf8)!)
    }

    func testPTYShellResize() async throws {
        let server = IOSSHShellServer(
            expectedUsername: "user",
            expectedPassword: "password",
            host: "localhost",
            port: 2234
        )
        try server.run()
        defer {
            server.end()
        }

        let connection = SSHConnection(
            host: server.host,
            port: server.port,
            authentication: server.credentials
        )
        try await connection.start()

        let terminal = SSHPseudoTerminal(
            term: "xterm-256color",
            size: .init(
                terminalCharacterWidth: 100,
                terminalRowHeight: 30,
                terminalPixelWidth: 1000,
                terminalPixelHeight: 600
            ),
            terminalModes: .init([.ECHO: 1])
        )
        let shell = try await connection.requestShell(pty: terminal)
        try await shell.resize(
            to: .init(
                terminalCharacterWidth: 80,
                terminalRowHeight: 24,
                terminalPixelWidth: 720,
                terminalPixelHeight: 480
            )
        )
        try await shell.close()
        await connection.cancel()

        XCTAssertEqual(server.ptyRequests.count, 1)
        XCTAssertEqual(server.windowChangeRequests.count, 1)
    }
}

private actor ShellActor {
    private(set) var result = Data()
    private(set) var isEnded = false
    private(set) var hasFailed = false

    func addData(_ data: Data) {
        result.append(data)
    }

    func fail() {
        hasFailed = true
    }

    func end() {
        isEnded = true
    }
}
