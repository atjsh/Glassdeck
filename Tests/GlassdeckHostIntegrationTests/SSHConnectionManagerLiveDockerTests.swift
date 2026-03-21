import Foundation
@testable import GlassdeckCore
import XCTest

final class SSHConnectionManagerLiveDockerTests: XCTestCase {
    func testPasswordAuthCanOpenShellAndApplyRuntimeResize() async throws {
        let configuration = try LiveDockerTestConfiguration.load()
        let manager = SSHConnectionManager()
        let profile = ConnectionProfile(
            name: "Docker Password",
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            authMethod: .password
        )

        let connectionID = try await manager.connect(to: profile, password: configuration.password)
        do {
            let shell = try await manager.openShell(
                connectionID: connectionID,
                configuration: ShellLaunchConfiguration(
                    term: "xterm-256color",
                    size: TerminalSize(columns: 90, rows: 31)
                )
            )
            let recorder = ShellOutputRecorder()
            let outputTask = makeOutputTask(for: shell, recorder: recorder)

            try await shell.write(
                Data("printf 'GLASSDECK_INITIAL:'; stty size; printf '\\n'\n".utf8)
            )

            try await waitForOutput("GLASSDECK_INITIAL:", recorder: recorder)
            try await waitForOutput("31 90", recorder: recorder)
            try await shell.resize(
                to: TerminalSize(columns: 132, rows: 43),
                pixelSize: TerminalPixelSize(width: 1320, height: 860)
            )
            try await shell.write(
                Data("printf 'GLASSDECK_AFTER:'; stty size; printf '\\n'; ~/bin/health-check.sh; exit\n".utf8)
            )

            try await waitForOutput("GLASSDECK_AFTER:", recorder: recorder)
            try await waitForOutput("43 132", recorder: recorder)
            try await waitForOutput("GLASSDECK_SSH_OK", recorder: recorder)

            await manager.disconnect(id: connectionID)
            await outputTask.value

            let output = await recorder.snapshot
            XCTAssertTrue(output.contains("/home/glassdeck"))
        } catch {
            await manager.disconnect(id: connectionID)
            await manager.remove(id: connectionID)
            throw error
        }

        await manager.remove(id: connectionID)
    }

    func testKeyAuthCanOpenShellAndReadSeededTestdata() async throws {
        let configuration = try LiveDockerTestConfiguration.load()
        let keyID = "live-docker-\(UUID().uuidString)"
        let keyData = try Data(contentsOf: configuration.privateKeyURL)

        try? SSHKeyManager.shared.deleteKey(id: keyID)
        SSHKeyManager.shared.savePrivateKey(id: keyID, keyData: keyData)
        defer {
            try? SSHKeyManager.shared.deleteKey(id: keyID)
        }

        let manager = SSHConnectionManager()
        let profile = ConnectionProfile(
            name: "Docker Key",
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            authMethod: .sshKey,
            sshKeyID: keyID
        )

        let connectionID = try await manager.connect(to: profile)
        do {
            let shell = try await manager.openShell(connectionID: connectionID)
            let recorder = ShellOutputRecorder()
            let outputTask = makeOutputTask(for: shell, recorder: recorder)

            try await shell.write(
                Data(
                    """
                    echo GLASSDECK_LIVE_KEY
                    pwd
                    ls ~/testdata
                    ~/bin/health-check.sh
                    exit
                    """.utf8
                )
            )

            try await waitForOutput("GLASSDECK_LIVE_KEY", recorder: recorder)
            try await waitForOutput("preview.txt", recorder: recorder)
            try await waitForOutput("GLASSDECK_SSH_OK", recorder: recorder)

            await manager.disconnect(id: connectionID)
            await outputTask.value

            let output = await recorder.snapshot
            XCTAssertTrue(output.contains("nano-target.txt"))
            XCTAssertTrue(output.contains("/home/glassdeck"))
        } catch {
            await manager.disconnect(id: connectionID)
            await manager.remove(id: connectionID)
            throw error
        }

        await manager.remove(id: connectionID)
    }

    private func makeOutputTask(
        for shell: any InteractiveShell,
        recorder: ShellOutputRecorder
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await chunk in shell.output {
                    await recorder.append(chunk)
                }
            } catch {
                await recorder.record(error: error)
            }
        }
    }

    private func waitForOutput(
        _ marker: String,
        recorder: ShellOutputRecorder,
        timeout: Duration = .seconds(15)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            let snapshot = await recorder.snapshot
            if snapshot.contains(marker) {
                return
            }

            if let error = await recorder.errorDescription {
                throw LiveDockerTestError.outputStreamFailed(marker: marker, output: snapshot, error: error)
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw LiveDockerTestError.missingMarker(marker: marker, output: await recorder.snapshot)
    }
}

private actor ShellOutputRecorder {
    private var output = ""
    private var error: String?

    func append(_ data: Data) {
        output.append(String(decoding: data, as: UTF8.self))
    }

    func record(error: Error) {
        self.error = String(describing: error)
    }

    var snapshot: String {
        output
    }

    var errorDescription: String? {
        error
    }
}

private struct LiveDockerTestConfiguration {
    let host: String
    let port: Int
    let username: String
    let password: String
    let privateKeyURL: URL

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard environment["GLASSDECK_LIVE_SSH_ENABLED"] == "1" else {
            throw XCTSkip("Set GLASSDECK_LIVE_SSH_ENABLED=1 to run the live Docker SSH integration tests.")
        }

        guard
            let host = environment["GLASSDECK_LIVE_SSH_HOST"],
            let portString = environment["GLASSDECK_LIVE_SSH_PORT"],
            let port = Int(portString),
            let username = environment["GLASSDECK_LIVE_SSH_USER"],
            let password = environment["GLASSDECK_LIVE_SSH_PASSWORD"],
            let keyPath = environment["GLASSDECK_LIVE_SSH_KEY_PATH"]
        else {
            throw XCTSkip("Live Docker SSH test environment variables are incomplete.")
        }

        return Self(
            host: host,
            port: port,
            username: username,
            password: password,
            privateKeyURL: URL(fileURLWithPath: keyPath)
        )
    }
}

private enum LiveDockerTestError: LocalizedError {
    case missingMarker(marker: String, output: String)
    case outputStreamFailed(marker: String, output: String, error: String)

    var errorDescription: String? {
        switch self {
        case .missingMarker(let marker, let output):
            return "Timed out waiting for output marker '\(marker)'. Output so far:\n\(output)"
        case .outputStreamFailed(let marker, let output, let error):
            return "Shell output failed while waiting for '\(marker)': \(error)\nOutput so far:\n\(output)"
        }
    }
}
