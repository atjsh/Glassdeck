import Foundation
@testable import SSHClient
import XCTest

final class SSHShellPTYTests: XCTestCase {
    var server: IOSSHShellServer!
    var connection: SSHConnection!

    override func setUp() {
        server = IOSSHShellServer(
            expectedUsername: "user",
            expectedPassword: "password",
            host: "localhost",
            port: 2233
        )
        try! server.run()
        connection = SSHConnection(
            host: server.host,
            port: server.port,
            authentication: server.credentials
        )
    }

    override func tearDown() {
        connection.cancel {}
        server.end()
    }

    func testShellLaunchesWithPTY() throws {
        let shell = try launchShell()
        XCTAssertEqual(shell.states, [])
        XCTAssertEqual(shell.state, .ready)
        XCTAssertEqual(server.ptyRequests.count, 1)
        let request = server.ptyRequests[0]
        XCTAssertEqual(request.term, "xterm-256color")
        XCTAssertEqual(request.terminalCharacterWidth, 120)
        XCTAssertEqual(request.terminalRowHeight, 40)
        XCTAssertEqual(request.terminalPixelWidth, 960)
        XCTAssertEqual(request.terminalPixelHeight, 600)
        XCTAssertEqual(request.terminalModes, .init([.ECHO: 1]))

        let exp = XCTestExpectation()
        shell.shell.write("ping\n".data(using: .utf8)!) { result in
            XCTAssert(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        wait(timeout: 0.5)
        XCTAssertEqual(shell.data.count, 1)
        XCTAssertEqual(shell.data[0], "ping\n".data(using: .utf8))

        let closeExp = XCTestExpectation()
        shell.shell.close { result in
            XCTAssert(result.isSuccess)
            closeExp.fulfill()
        }
        wait(for: [closeExp], timeout: 2)
    }

    func testShellLaunchesWithoutPTY() throws {
        let exp = XCTestExpectation()
        var shell: SSHShell?
        connection.start(withTimeout: 2) { result in
            switch result {
            case .success:
                self.connection.requestShell(withTimeout: 15) { result in
                    switch result {
                    case .success(let success):
                        shell = success
                    case .failure:
                        break
                    }
                    exp.fulfill()
                }
            case .failure:
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
        XCTAssertEqual(server.ptyRequests.count, 0)
        XCTAssertEqual(shell?.state, .ready)

        let closeExp = XCTestExpectation()
        shell?.close { result in
            XCTAssert(result.isSuccess)
            closeExp.fulfill()
        }
        wait(for: [closeExp], timeout: 2)
    }

    func testShellResizeSendsWindowChange() throws {
        let shell = try launchShell()
        let size = SSHWindowSize(
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 720,
            terminalPixelHeight: 480
        )
        let exp = XCTestExpectation()
        shell.shell.resize(to: size) { result in
            XCTAssert(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        wait(timeout: 0.2)
        XCTAssertEqual(server.windowChangeRequests.count, 1)
        let request = server.windowChangeRequests[0]
        XCTAssertEqual(request.terminalCharacterWidth, size.terminalCharacterWidth)
        XCTAssertEqual(request.terminalRowHeight, size.terminalRowHeight)
        XCTAssertEqual(request.terminalPixelWidth, size.terminalPixelWidth)
        XCTAssertEqual(request.terminalPixelHeight, size.terminalPixelHeight)
    }

    private func launchShell() throws -> EmbeddedShell {
        let exp = XCTestExpectation()
        var shell: EmbeddedShell?
        connection.start(withTimeout: 2) { result in
            switch result {
            case .success:
                let terminal = SSHPseudoTerminal(
                    term: "xterm-256color",
                    size: .init(
                        terminalCharacterWidth: 120,
                        terminalRowHeight: 40,
                        terminalPixelWidth: 960,
                        terminalPixelHeight: 600
                    ),
                    terminalModes: .init([.ECHO: 1])
                )
                self.connection.requestShell(pty: terminal, withTimeout: 15) { result in
                    switch result {
                    case .success(let success):
                        shell = EmbeddedShell(shell: success)
                    case .failure:
                        break
                    }
                    exp.fulfill()
                }
            case .failure:
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
        if let shell {
            return shell
        }
        struct AError: Error {}
        throw AError()
    }
}

private class EmbeddedShell {
    let shell: SSHShell

    var state: SSHShell.State {
        shell.state
    }

    private(set) var states: [SSHShell.State] = []
    private(set) var data: [Data] = []

    init(shell: SSHShell) {
        self.shell = shell
        self.shell.stateUpdateHandler = { state in
            self.states.append(state)
        }
        self.shell.readHandler = { data in
            self.data.append(data)
        }
    }
}
