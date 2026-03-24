import XCTest

@MainActor
final class DockerLiveProbeUITests: XCTestCase {
    private enum ProbeMarker {
        static let seeded = "docker-probe-seeded"
        static let live = "docker-probe-live"
        static let commandInjectionSuccess = "GLASSDECK_UI_COMMAND_INJECTION_OK"
        static let seededTranscriptMarkers = [
            "GLASSDECK_KEY_OK",
            "GLASSDECK_PASSWORD_OK",
            "GLASSDECK_SSH_OK",
            "preview.txt",
        ]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPromptOnlyProbeShowsShellPromptAndCheckpointNaming() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = try launchSeededLiveDockerProbeApp(
            configuration: configuration,
            connectionName: "Docker Probe Prompt",
            requirePreviewSurface: false
        )

        assertConnectedTerminal(for: app)
        waitForTerminalToBecomeUsable(in: app, timeout: 30)
        waitForLivePromptSummary(in: app, timeout: 30)

        let promptCheckpoint = captureProbeCheckpoint(
            in: app,
            prefix: ProbeMarker.seeded,
            phase: "prompt only",
            step: 1,
            kind: "pre command"
        )
        XCTAssertEqual(
            promptCheckpoint,
            probeCheckpointName(
                prefix: ProbeMarker.seeded,
                phase: "prompt only",
                step: 1,
                kind: "pre command"
            )
        )

        let summary = terminalRenderSummaryText(in: app)
        XCTAssertTrue(
            summary.contains("glassdeck@") || summary.contains("root@"),
            "Expected a shell prompt marker, got '\(summary)'."
        )
        XCTAssertFalse(
            ProbeMarker.seededTranscriptMarkers.contains(where: summary.contains),
            "Expected live prompt output, got seeded preview transcript '\(summary)'."
        )
    }

    func testCommandInjectionOnlyProbeInjectsFullCommandAndCapturesSummary() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = try launchSeededLiveDockerProbeApp(
            configuration: configuration,
            connectionName: "Docker Probe Command",
            requirePreviewSurface: false
        )
        let command = "echo \(ProbeMarker.commandInjectionSuccess)\n"
        let expectedCheckpoint = probeCheckpointName(
            prefix: ProbeMarker.live,
            phase: "command only",
            step: 2,
            kind: "after command"
        )

        assertConnectedTerminal(for: app)
        waitForTerminalToBecomeUsable(in: app, timeout: 30)
        waitForLivePromptSummary(in: app, timeout: 30)

        let checkpointAfterCommand = captureProbeCheckpoint(
            in: app,
            prefix: ProbeMarker.live,
            phase: "command only",
            step: 1,
            kind: "before command"
        )

        enterTerminalCommand(command, in: app)
        waitForTerminalRenderSummary(
            containing: ProbeMarker.commandInjectionSuccess,
            in: app,
            timeout: 30
        )

        let doneCheckpoint = captureProbeCheckpoint(
            in: app,
            prefix: ProbeMarker.live,
            phase: "command only",
            step: 2,
            kind: "after command"
        )
        XCTAssertEqual(
            checkpointAfterCommand,
            probeCheckpointName(
                prefix: ProbeMarker.live,
                phase: "command only",
                step: 1,
                kind: "before command"
            )
        )
        XCTAssertEqual(doneCheckpoint, expectedCheckpoint)
        XCTAssertNotEqual(checkpointAfterCommand, doneCheckpoint)
        XCTAssertTrue(terminalRenderSummaryText(in: app).contains(ProbeMarker.commandInjectionSuccess))
    }

    func testRenderOnlyProbeCapturesVisibleTerminalSurface() throws {
        let configuration = try LiveDockerUITestConfiguration.load()
        let app = try launchSeededLiveDockerProbeApp(
            configuration: configuration,
            connectionName: "Docker Probe Render",
            requirePreviewSurface: false
        )

        let launchCheckpoint = captureProbeCheckpoint(
            in: app,
            prefix: ProbeMarker.live,
            phase: "render only",
            step: 1,
            kind: "launch"
        )
        XCTAssertEqual(
            launchCheckpoint,
            probeCheckpointName(
                prefix: ProbeMarker.live,
                phase: "render only",
                step: 1,
                kind: "launch"
            )
        )

        assertConnectedTerminal(for: app)
        waitForTerminalToBecomeUsable(in: app, timeout: 30)
        waitForLivePromptSummary(in: app, timeout: 30)
        let terminalSurface = app.otherElements["terminal-surface-view"].firstMatch
        assertScreenshotContainsChromaticPixels(
            of: terminalSurface,
            named: "docker-probe-render-only-terminal",
            minimumChromaticSamples: 1
        )

        let visibleCheckpoint = captureProbeCheckpoint(
            in: app,
            prefix: ProbeMarker.live,
            phase: "render only",
            step: 2,
            kind: "after render"
        )
        XCTAssertEqual(
            visibleCheckpoint,
            probeCheckpointName(
                prefix: ProbeMarker.live,
                phase: "render only",
                step: 2,
                kind: "after render"
            )
        )
    }

    private func waitForLivePromptSummary(
        in app: XCUIApplication,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let summary = terminalRenderSummaryText(in: app)
            let hasPrompt = summary.contains("glassdeck@") || summary.contains("root@")
            let stillSeeded = ProbeMarker.seededTranscriptMarkers.contains(where: summary.contains)
            if hasPrompt && !stillSeeded {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        let summary = terminalRenderSummaryText(in: app)
        captureTerminalDiagnostics(in: app, named: "docker-probe-prompt-summary-timeout")
        XCTFail(
            "Expected live prompt output instead of seeded transcript, got '\(summary)'.",
            file: file,
            line: line
        )
    }
}
