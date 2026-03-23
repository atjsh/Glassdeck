import Foundation

public enum ProcessOutputMode: Sendable, Equatable {
    case captureOnly
    case captureAndStreamTimestamped
    case captureAndStreamTimestampedFiltered(ProcessOutputFilter)
}

public enum ProcessOutputStream: String, Sendable, Equatable {
    case standardOutput = "stdout"
    case standardError = "stderr"
}

public enum ProcessOutputFilter: String, Sendable, Equatable {
    case xcodebuild

    func shouldEmit(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch self {
        case .xcodebuild:
            if trimmed.contains("Metadata extraction skipped") {
                return false
            }

            if trimmed.contains("IDETestOperationsObserverDebug:") {
                return false
            }

            if trimmed == "Testing started" {
                return false
            }

            if trimmed.contains("Interface orientation changed") {
                return false
            }

            return trimmed.contains("error:")
                || trimmed.contains("warning:")
                || trimmed.contains("failed")
                || trimmed.contains("passed")
                || trimmed.contains("skipped")
                || trimmed.contains("encountered an error")
                || trimmed.contains("Test Suite")
                || trimmed.contains("Test Case")
                || trimmed.contains("Testing started")
                || trimmed.contains("Testing failed:")
                || trimmed.contains("Test session")
                || trimmed.contains("** TEST")
                || trimmed.contains("Command line invocation:")
                || trimmed.contains("xcodebuild ")
                || trimmed.contains("Writing result bundle at path:")
                || trimmed.hasSuffix(".xcresult")
                || trimmed.contains(".swift:")
                || trimmed.hasPrefix("t =")
        }
    }
}

public protocol ProcessOutputSink: Sendable {
    func write(_ renderedLine: String, stream: ProcessOutputStream)
}

public struct ProcessInvocation: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environment: [String: String]
    public let capturedStandardOutputPath: URL?
    public let capturedStandardErrorPath: URL?
    public let retainedOutputByteLimit: Int?
    public let outputMode: ProcessOutputMode

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        capturedStandardOutputPath: URL? = nil,
        capturedStandardErrorPath: URL? = nil,
        retainedOutputByteLimit: Int? = nil,
        outputMode: ProcessOutputMode = .captureOnly
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.capturedStandardOutputPath = capturedStandardOutputPath
        self.capturedStandardErrorPath = capturedStandardErrorPath
        self.retainedOutputByteLimit = retainedOutputByteLimit
        self.outputMode = outputMode
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var isSuccess: Bool {
        exitCode == 0
    }
}

public enum ProcessRunnerError: Error, LocalizedError {
    case commandNotExecutable(String)
    case launchFailed(Error)
    case nonzeroExit(ProcessResult)

    public var errorDescription: String? {
        switch self {
        case let .commandNotExecutable(executable):
            "Process executable does not exist at path: \(executable)"
        case let .launchFailed(error):
            "Failed to launch process: \(error)"
        case let .nonzeroExit(result):
            "Process exited with code \(result.exitCode)"
        }
    }
}

public protocol ProcessRunner {
    func run(_ invocation: ProcessInvocation) async throws -> ProcessResult
}

public final class DefaultProcessRunner: ProcessRunner, Sendable {
    private final class PipeCapture: @unchecked Sendable {
        private let handle: FileHandle
        private let queue: DispatchQueue
        private let stream: ProcessOutputStream
        private let captureHandle: FileHandle?
        private let retainedOutputByteLimit: Int?
        private let outputMode: ProcessOutputMode
        private let outputSink: ProcessOutputSink
        private let nowProvider: @Sendable () -> Date
        private let timestampFormatter: ISO8601DateFormatter
        private(set) var data = Data()
        private var pending = Data()
        private var suppressedLowSignalLineCount = 0

        init(
            handle: FileHandle,
            label: String,
            stream: ProcessOutputStream,
            capturePath: URL?,
            retainedOutputByteLimit: Int?,
            outputMode: ProcessOutputMode,
            outputSink: ProcessOutputSink,
            nowProvider: @escaping @Sendable () -> Date,
            timestampFormatter: ISO8601DateFormatter
        ) throws {
            self.handle = handle
            self.queue = DispatchQueue(label: label)
            self.stream = stream
            self.captureHandle = try Self.makeCaptureHandle(at: capturePath)
            self.retainedOutputByteLimit = retainedOutputByteLimit
            self.outputMode = outputMode
            self.outputSink = outputSink
            self.nowProvider = nowProvider
            self.timestampFormatter = timestampFormatter
        }

        func start(group: DispatchGroup) {
            group.enter()
            queue.async {
                defer { group.leave() }
                while true {
                    let chunk = self.handle.availableData
                    if chunk.isEmpty {
                        self.flushPending()
                        self.captureHandle?.closeFile()
                        break
                    }
                    self.capture(chunk)
                    self.stream(chunk)
                }
            }
        }

        private static func makeCaptureHandle(at path: URL?) throws -> FileHandle? {
            guard let path else { return nil }

            let fileManager = FileManager.default
            let parentDirectory = path.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDirectory.path) {
                try fileManager.createDirectory(
                    at: parentDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
            if fileManager.fileExists(atPath: path.path) {
                try fileManager.removeItem(at: path)
            }
            guard fileManager.createFile(atPath: path.path, contents: nil) else {
                throw NSError(
                    domain: "DefaultProcessRunner.PipeCapture",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create capture file at \(path.path)"]
                )
            }
            return try FileHandle(forWritingTo: path)
        }

        private func capture(_ chunk: Data) {
            captureHandle?.write(chunk)
            appendRetainedBytes(chunk)
        }

        private func appendRetainedBytes(_ chunk: Data) {
            guard let retainedOutputByteLimit else {
                data.append(chunk)
                return
            }

            let byteLimit = max(0, retainedOutputByteLimit)
            guard byteLimit > 0 else {
                data.removeAll(keepingCapacity: true)
                return
            }

            if chunk.count >= byteLimit {
                data = Data(chunk.suffix(byteLimit))
                return
            }

            data.append(chunk)
            let overflow = data.count - byteLimit
            if overflow > 0 {
                data.removeFirst(min(overflow, data.count))
            }
        }

        private func stream(_ chunk: Data) {
            guard outputMode != .captureOnly else { return }
            pending.append(chunk)

            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending.prefix(upTo: newlineIndex)
                pending.removeSubrange(...newlineIndex)
                handleDecodedLine(String(decoding: lineData, as: UTF8.self))
            }
        }

        private func flushPending() {
            guard outputMode != .captureOnly else { return }
            if !pending.isEmpty {
                let trailingLine = String(decoding: pending, as: UTF8.self)
                pending.removeAll(keepingCapacity: false)
                handleDecodedLine(trailingLine)
            }
            flushSuppressedLowSignalSummaryIfNeeded()
        }

        private func handleDecodedLine(_ line: String) {
            let sanitizedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line

            switch outputMode {
            case .captureOnly:
                return
            case .captureAndStreamTimestamped:
                flushSuppressedLowSignalSummaryIfNeeded()
                emitLine(sanitizedLine)
            case let .captureAndStreamTimestampedFiltered(filter):
                if filter.shouldEmit(sanitizedLine) {
                    flushSuppressedLowSignalSummaryIfNeeded()
                    emitLine(sanitizedLine)
                } else {
                    suppressedLowSignalLineCount += 1
                }
            }
        }

        private func flushSuppressedLowSignalSummaryIfNeeded() {
            guard suppressedLowSignalLineCount > 0 else { return }
            let pluralSuffix = suppressedLowSignalLineCount == 1 ? "" : "s"
            emitLine("... suppressed \(suppressedLowSignalLineCount) low-signal xcodebuild line\(pluralSuffix)")
            suppressedLowSignalLineCount = 0
        }

        private func emitLine(_ line: String) {
            let timestamp = timestampFormatter.string(from: nowProvider())
            outputSink.write(
                "[\(timestamp)] [\(stream.rawValue)] \(line)",
                stream: stream
            )
        }
    }

    private let outputSink: ProcessOutputSink
    private let nowProvider: @Sendable () -> Date

    public init(
        outputSink: ProcessOutputSink = TimestampedTerminalOutputSink(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.outputSink = outputSink
        self.nowProvider = nowProvider
    }

    public func run(_ invocation: ProcessInvocation) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: invocation.executable) else {
            throw ProcessRunnerError.commandNotExecutable(invocation.executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory

        if !invocation.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(invocation.environment) { _, new in new }
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let captureGroup = DispatchGroup()
        let stdoutCapture: PipeCapture
        let stderrCapture: PipeCapture
        do {
            stdoutCapture = try PipeCapture(
                handle: stdout.fileHandleForReading,
                label: "GlassdeckBuild.stdoutCapture",
                stream: .standardOutput,
                capturePath: invocation.capturedStandardOutputPath,
                retainedOutputByteLimit: invocation.retainedOutputByteLimit,
                outputMode: invocation.outputMode,
                outputSink: outputSink,
                nowProvider: nowProvider,
                timestampFormatter: makeTimestampFormatter()
            )
            stderrCapture = try PipeCapture(
                handle: stderr.fileHandleForReading,
                label: "GlassdeckBuild.stderrCapture",
                stream: .standardError,
                capturePath: invocation.capturedStandardErrorPath,
                retainedOutputByteLimit: invocation.retainedOutputByteLimit,
                outputMode: invocation.outputMode,
                outputSink: outputSink,
                nowProvider: nowProvider,
                timestampFormatter: makeTimestampFormatter()
            )
        } catch {
            throw ProcessRunnerError.launchFailed(error)
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error)
        }

        stdoutCapture.start(group: captureGroup)
        stderrCapture.start(group: captureGroup)
        process.waitUntilExit()
        await withCheckedContinuation { continuation in
            captureGroup.notify(queue: .global(qos: .utility)) {
                continuation.resume()
            }
        }

        let result = ProcessResult(
            exitCode: Int(process.terminationStatus),
            standardOutput: String(decoding: stdoutCapture.data, as: UTF8.self),
            standardError: String(decoding: stderrCapture.data, as: UTF8.self)
        )
        if result.exitCode != 0 {
            throw ProcessRunnerError.nonzeroExit(result)
        }

        return result
    }

    private func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

public final class TimestampedTerminalOutputSink: ProcessOutputSink, @unchecked Sendable {
    private let lock = NSLock()

    public init() {}

    public func write(_ renderedLine: String, stream: ProcessOutputStream) {
        lock.lock()
        defer { lock.unlock() }

        let payload = Data((renderedLine + "\n").utf8)
        switch stream {
        case .standardOutput:
            FileHandle.standardOutput.write(payload)
        case .standardError:
            FileHandle.standardError.write(payload)
        }
    }
}
