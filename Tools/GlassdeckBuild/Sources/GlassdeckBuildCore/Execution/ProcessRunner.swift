import Foundation

public struct ProcessInvocation: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environment: [String: String]

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
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
        private(set) var data = Data()

        init(handle: FileHandle, label: String) {
            self.handle = handle
            self.queue = DispatchQueue(label: label)
        }

        func start(group: DispatchGroup) {
            group.enter()
            queue.async {
                defer { group.leave() }
                self.data = self.handle.readDataToEndOfFile()
            }
        }
    }

    public init() {}

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
        let stdoutCapture = PipeCapture(
            handle: stdout.fileHandleForReading,
            label: "GlassdeckBuild.stdoutCapture"
        )
        let stderrCapture = PipeCapture(
            handle: stderr.fileHandleForReading,
            label: "GlassdeckBuild.stderrCapture"
        )

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
}
