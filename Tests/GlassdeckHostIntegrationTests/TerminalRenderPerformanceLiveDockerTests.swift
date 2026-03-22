import Foundation
import UIKit
@testable import Glassdeck
@testable import GlassdeckCore
import XCTest

@MainActor
final class TerminalRenderPerformanceLiveDockerTests: XCTestCase {

    // MARK: - Tests

    func testHeavyOutputDoesNotStarveMainRunLoop() async throws {
        let config = try RenderPerfDockerConfig.load()
        let harness = try await makeConnectedHarness(config: config)
        defer { harness.cleanup() }

        // Record main-queue callback timestamps during heavy output
        var timestamps: [CFAbsoluteTime] = [CFAbsoluteTimeGetCurrent()]
        var probing = true
        let probeInterval: TimeInterval = 0.05 // 50ms

        func scheduleProbe() {
            DispatchQueue.main.asyncAfter(deadline: .now() + probeInterval) {
                guard probing else { return }
                timestamps.append(CFAbsoluteTimeGetCurrent())
                scheduleProbe()
            }
        }
        scheduleProbe()

        // Send heavy output command
        try await harness.shell.write(Data(
            "cat /dev/urandom | base64 | head -c 500000; echo GLASSDECK_PERF_DONE\n".utf8
        ))

        try await waitForOutput("GLASSDECK_PERF_DONE", recorder: harness.recorder, timeout: .seconds(30))
        probing = false

        // Drain any pending callbacks
        try await Task.sleep(for: .milliseconds(200))

        // Measure max gap between consecutive timestamps
        var maxGap: TimeInterval = 0
        for i in 1..<timestamps.count {
            let gap = timestamps[i] - timestamps[i - 1]
            maxGap = max(maxGap, gap)
        }

        let budget: TimeInterval = {
            #if targetEnvironment(simulator)
            return 0.200
            #else
            return 0.100
            #endif
        }()

        XCTAssertGreaterThan(
            timestamps.count, 2,
            "Expected at least 2 probe callbacks during heavy output, got \(timestamps.count)."
        )
        XCTAssertLessThanOrEqual(
            maxGap, budget,
            "Main run loop was starved: max gap \(String(format: "%.0f", maxGap * 1000))ms exceeds \(String(format: "%.0f", budget * 1000))ms budget."
        )
    }

    func testHeavyOutputRenderThroughputStaysWithinBudget() async throws {
        let config = try RenderPerfDockerConfig.load()
        let harness = try await makeConnectedHarness(config: config)
        defer { harness.cleanup() }

        let startRenderCount = harness.surface.renderCount
        let startTime = CFAbsoluteTimeGetCurrent()

        try await harness.shell.write(Data(
            "cat /dev/urandom | base64 | head -c 500000; echo GLASSDECK_THROUGHPUT_DONE\n".utf8
        ))

        try await waitForOutput("GLASSDECK_THROUGHPUT_DONE", recorder: harness.recorder, timeout: .seconds(30))
        try await Task.sleep(for: .milliseconds(200))

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let renderDelta = harness.surface.renderCount - startRenderCount

        let maxRenders: Int = {
            #if targetEnvironment(simulator)
            return 200
            #else
            return 120
            #endif
        }()

        XCTAssertLessThanOrEqual(
            renderDelta, maxRenders,
            "Render coalescing failed: \(renderDelta) renders for 500KB output exceeds budget of \(maxRenders)."
        )
        XCTAssertLessThanOrEqual(
            elapsed, 15.0,
            "Heavy output took \(String(format: "%.1f", elapsed))s, exceeds 15s budget."
        )
    }

    func testIdleCursorBlinkDoesNotProduceExcessiveRenders() async throws {
        let config = try RenderPerfDockerConfig.load()
        let harness = try await makeConnectedHarness(config: config)
        defer { harness.cleanup() }

        // Send a simple command and wait for prompt
        try await harness.shell.write(Data("echo GLASSDECK_BLINK_READY\n".utf8))
        try await waitForOutput("GLASSDECK_BLINK_READY", recorder: harness.recorder)

        // Let the terminal settle
        try await Task.sleep(for: .milliseconds(500))

        let startRenderCount = harness.surface.renderCount
        let measureSeconds: TimeInterval = 5.0

        // Wait while cursor blink timer fires
        try await Task.sleep(for: .seconds(Int(measureSeconds)))

        let renderDelta = harness.surface.renderCount - startRenderCount

        // Cursor blinks at 0.6s interval → ~8 blinks in 5s + margin
        XCTAssertLessThanOrEqual(
            renderDelta, 15,
            "Idle cursor blink produced \(renderDelta) renders in \(Int(measureSeconds))s, expected ≤15."
        )
    }

    // MARK: - Harness

    private struct ConnectedHarness {
        let surface: GhosttySurface
        let shell: any InteractiveShell
        let recorder: ShellOutputRecorder
        let window: UIWindow
        private let manager: SSHConnectionManager
        private let connectionID: UUID
        private let outputTask: Task<Void, Never>

        init(
            surface: GhosttySurface,
            shell: any InteractiveShell,
            recorder: ShellOutputRecorder,
            window: UIWindow,
            manager: SSHConnectionManager,
            connectionID: UUID,
            outputTask: Task<Void, Never>
        ) {
            self.surface = surface
            self.shell = shell
            self.recorder = recorder
            self.window = window
            self.manager = manager
            self.connectionID = connectionID
            self.outputTask = outputTask
        }

        @MainActor
        func cleanup() {
            window.isHidden = true
            Task {
                await manager.disconnect(id: connectionID)
                await manager.remove(id: connectionID)
                outputTask.cancel()
            }
        }
    }

    private func makeConnectedHarness(config: RenderPerfDockerConfig) async throws -> ConnectedHarness {
        // Set up the SSH connection
        let manager = SSHConnectionManager()
        let profile = ConnectionProfile(
            name: "Docker Perf",
            host: config.host,
            port: config.port,
            username: config.username,
            authMethod: .password
        )
        let connectionID = try await manager.connect(to: profile, password: config.password)

        let shell = try await manager.openShell(
            connectionID: connectionID,
            configuration: ShellLaunchConfiguration(
                term: "xterm-256color",
                size: TerminalSize(columns: 80, rows: 24)
            )
        )

        // Set up the GhosttySurface in a test window
        let terminalConfig = TerminalConfiguration(fontSize: 14, scrollbackLines: 0, cursorBlink: true)
        let surface = try GhosttySurface(configuration: terminalConfig)

        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached })
        else {
            throw XCTestError(.failureWhileWaiting)
        }

        let bounds = GhosttySurface.previewBounds(
            for: TerminalSize(columns: 80, rows: 24),
            configuration: terminalConfig
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = bounds
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        vc.view.frame = bounds

        surface.frame = vc.view.bounds
        vc.view.addSubview(surface)
        surface.setFocused(true)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        surface.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        // Bridge shell output → surface via TerminalIO
        let recorder = ShellOutputRecorder()
        let outputTask = Task { [weak surface] in
            do {
                for try await chunk in shell.output {
                    await recorder.append(chunk)
                    await MainActor.run {
                        surface?.writeToTerminal(chunk)
                    }
                }
            } catch {
                await recorder.record(error: error)
            }
        }

        return ConnectedHarness(
            surface: surface,
            shell: shell,
            recorder: recorder,
            window: window,
            manager: manager,
            connectionID: connectionID,
            outputTask: outputTask
        )
    }

    // MARK: - Utilities

    private func waitForOutput(
        _ marker: String,
        recorder: ShellOutputRecorder,
        timeout: Duration = .seconds(15)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            let snapshot = await recorder.snapshot
            if snapshot.contains(marker) { return }

            if let error = await recorder.errorDescription {
                throw RenderPerfTestError.outputStreamFailed(
                    marker: marker, output: snapshot, error: error
                )
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw RenderPerfTestError.missingMarker(
            marker: marker, output: await recorder.snapshot
        )
    }
}

// MARK: - Support Types

private actor ShellOutputRecorder {
    private var output = ""
    private var error: String?

    func append(_ data: Data) {
        output.append(String(decoding: data, as: UTF8.self))
    }

    func record(error: Error) {
        self.error = String(describing: error)
    }

    var snapshot: String { output }
    var errorDescription: String? { error }
}

private struct RenderPerfDockerConfig {
    let host: String
    let port: Int
    let username: String
    let password: String

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        guard environment["GLASSDECK_LIVE_SSH_ENABLED"] == "1" else {
            throw XCTSkip("Set GLASSDECK_LIVE_SSH_ENABLED=1 to run terminal render performance tests.")
        }
        guard
            let host = environment["GLASSDECK_LIVE_SSH_HOST"],
            let portString = environment["GLASSDECK_LIVE_SSH_PORT"],
            let port = Int(portString),
            let username = environment["GLASSDECK_LIVE_SSH_USER"],
            let password = environment["GLASSDECK_LIVE_SSH_PASSWORD"]
        else {
            throw XCTSkip("Live Docker SSH test environment variables are incomplete.")
        }
        return Self(host: host, port: port, username: username, password: password)
    }
}

private enum RenderPerfTestError: LocalizedError {
    case missingMarker(marker: String, output: String)
    case outputStreamFailed(marker: String, output: String, error: String)

    var errorDescription: String? {
        switch self {
        case .missingMarker(let marker, let output):
            "Timed out waiting for '\(marker)'. Output:\n\(output.suffix(500))"
        case .outputStreamFailed(let marker, let output, let error):
            "Shell failed while waiting for '\(marker)': \(error)\nOutput:\n\(output.suffix(500))"
        }
    }
}
