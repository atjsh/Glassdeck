import XCTest
@testable import GlassdeckBuildCore

final class ProcessRunnerTests: XCTestCase {
    func testDefaultProcessRunnerCanWriteFullStreamsToDiskWhileRetainingTailInMemory() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-process-runner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let stdoutPath = tempRoot.appendingPathComponent("stdout.log")
        let stderrPath = tempRoot.appendingPathComponent("stderr.log")
        let runner = DefaultProcessRunner()

        let result = try await runner.run(
            ProcessInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    "-c",
                    """
import sys
sys.stdout.write("start-" + ("x" * 256) + "-end\\n")
sys.stderr.write("begin-" + ("y" * 256) + "-done\\n")
""",
                ],
                capturedStandardOutputPath: stdoutPath,
                capturedStandardErrorPath: stderrPath,
                retainedOutputByteLimit: 32
            )
        )

        let stdoutLog = try String(contentsOf: stdoutPath, encoding: .utf8)
        let stderrLog = try String(contentsOf: stderrPath, encoding: .utf8)

        XCTAssertTrue(stdoutLog.hasPrefix("start-"))
        XCTAssertTrue(stdoutLog.hasSuffix("-end\n"))
        XCTAssertTrue(stderrLog.hasPrefix("begin-"))
        XCTAssertTrue(stderrLog.hasSuffix("-done\n"))
        XCTAssertLessThanOrEqual(result.standardOutput.utf8.count, 32)
        XCTAssertLessThanOrEqual(result.standardError.utf8.count, 32)
        XCTAssertTrue(result.standardOutput.hasSuffix("x-end\n"))
        XCTAssertTrue(result.standardError.hasSuffix("y-done\n"))
    }

    func testDefaultProcessRunnerStreamsTimestampedLinesWhenRequested() async throws {
        let sink = RecordingProcessOutputSink()
        let runner = DefaultProcessRunner(
            outputSink: sink,
            nowProvider: { Date(timeIntervalSince1970: 0) }
        )
        let result = try await runner.run(
            ProcessInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    "-c",
                    "import sys; sys.stdout.write('hello\\nworld\\n'); sys.stderr.write('boom\\n')",
                ],
                outputMode: .captureAndStreamTimestamped
            )
        )

        XCTAssertEqual(result.standardOutput, "hello\nworld\n")
        XCTAssertEqual(result.standardError, "boom\n")
        XCTAssertEqual(sink.events.count, 3)
        XCTAssertEqual(
            sink.events.filter { $0.stream == .standardOutput },
            [
                .init(stream: .standardOutput, renderedLine: "[1970-01-01T00:00:00.000Z] [stdout] hello"),
                .init(stream: .standardOutput, renderedLine: "[1970-01-01T00:00:00.000Z] [stdout] world"),
            ]
        )
        XCTAssertEqual(
            sink.events.filter { $0.stream == .standardError },
            [
                .init(stream: .standardError, renderedLine: "[1970-01-01T00:00:00.000Z] [stderr] boom"),
            ]
        )
    }

    func testDefaultProcessRunnerFiltersLowSignalXcodebuildLines() async throws {
        let sink = RecordingProcessOutputSink()
        let runner = DefaultProcessRunner(
            outputSink: sink,
            nowProvider: { Date(timeIntervalSince1970: 0) }
        )
        let result = try await runner.run(
            ProcessInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    "-c",
                    """
import sys
sys.stdout.write('Resolve Package Graph\\n')
sys.stdout.write('Resolved source packages:\\n')
sys.stdout.write('  swift-atomics: https://example.invalid\\n')
sys.stdout.write('    t =      nans Interface orientation changed to Portrait\\n')
sys.stdout.write(\"Test Case '-[GlassdeckTests example]' passed (0.1 seconds).\\n\")
sys.stdout.write('Testing started\\n')
sys.stderr.write('2026-03-24 00:31:02.333 xcodebuild[54021:4306489] [MT] IDETestOperationsObserverDebug: 20.091 elapsed -- Testing started completed.\\n')
sys.stderr.write('error: compile failed\\n')
""",
                ],
                outputMode: .captureAndStreamTimestampedFiltered(.xcodebuild)
            )
        )

        XCTAssertTrue(result.standardOutput.contains("Resolve Package Graph"))
        XCTAssertTrue(result.standardOutput.contains("Test Case '-[GlassdeckTests example]' passed"))
        XCTAssertTrue(result.standardError.contains("error: compile failed"))

        let renderedLines = sink.events.map(\.renderedLine)
        XCTAssertFalse(renderedLines.contains { $0.contains("Resolve Package Graph") })
        XCTAssertFalse(renderedLines.contains { $0.contains("Resolved source packages:") })
        XCTAssertFalse(renderedLines.contains { $0.contains("swift-atomics:") })
        XCTAssertFalse(renderedLines.contains { $0.contains("Interface orientation changed") })
        XCTAssertFalse(renderedLines.contains { $0.contains("IDETestOperationsObserverDebug") })
        XCTAssertFalse(renderedLines.contains { $0.contains("[stdout] Testing started") })
        let suppressionSummaries = renderedLines.filter { $0.contains("suppressed ") }
        XCTAssertEqual(suppressionSummaries.count, 3)
        XCTAssertTrue(suppressionSummaries.contains { $0.contains("suppressed 4 low-signal xcodebuild lines") })
        XCTAssertEqual(
            suppressionSummaries.filter { $0.contains("suppressed 1 low-signal xcodebuild line") }.count,
            2
        )
        XCTAssertTrue(renderedLines.contains { $0.contains("Test Case '-[GlassdeckTests example]' passed") })
        XCTAssertTrue(renderedLines.contains { $0.contains("error: compile failed") })
    }

    func testDefaultProcessRunnerCanStillStreamFullTimestampedOutput() async throws {
        let sink = RecordingProcessOutputSink()
        let runner = DefaultProcessRunner(
            outputSink: sink,
            nowProvider: { Date(timeIntervalSince1970: 0) }
        )
        _ = try await runner.run(
            ProcessInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    "-c",
                    "print('Resolve Package Graph')",
                ],
                outputMode: .captureAndStreamTimestamped
            )
        )

        XCTAssertTrue(
            sink.events.map(\.renderedLine).contains { $0.contains("Resolve Package Graph") }
        )
    }

    func testDefaultProcessRunnerCapturesLargeOutputWithoutDeadlock() async throws {
        let runner = DefaultProcessRunner()
        let result = try await runner.run(
            ProcessInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    "-c",
                    "import sys; sys.stdout.write('o' * 200000); sys.stderr.write('e' * 150000)",
                ]
            )
        )

        XCTAssertEqual(result.standardOutput.count, 200000)
        XCTAssertEqual(result.standardError.count, 150000)
    }
}

private final class RecordingProcessOutputSink: ProcessOutputSink, @unchecked Sendable {
    struct Event: Equatable {
        let stream: ProcessOutputStream
        let renderedLine: String
    }

    private let lock = NSLock()
    private(set) var events: [Event] = []

    func write(_ renderedLine: String, stream: ProcessOutputStream) {
        lock.lock()
        defer { lock.unlock() }
        events.append(Event(stream: stream, renderedLine: renderedLine))
    }
}
