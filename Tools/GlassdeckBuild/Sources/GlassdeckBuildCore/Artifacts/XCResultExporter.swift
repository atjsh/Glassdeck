import Foundation

public protocol XCResultExporting {
    func export(resultBundle: URL, outputDirectory: URL) async throws -> URL
}

public struct XCResultExporter: XCResultExporting {
    public enum Error: Swift.Error, LocalizedError {
        case missingResultBundle(URL)
        case missingRunnerOutput
        case executionFailed(String)
    }

    public let processRunner: ProcessRunner
    public let commandPath: String
    public let fileManager: FileManager
    public let outputFileName: String

    public init(
        processRunner: ProcessRunner = DefaultProcessRunner(),
        commandPath: String = "/usr/bin/xcrun",
        fileManager: FileManager = .default,
        outputFileName: String = "summary.json"
    ) {
        self.processRunner = processRunner
        self.commandPath = commandPath
        self.fileManager = fileManager
        self.outputFileName = outputFileName
    }

    public func export(resultBundle: URL, outputDirectory: URL) async throws -> URL {
        guard fileManager.fileExists(atPath: resultBundle.path) else {
            throw Error.missingResultBundle(resultBundle)
        }

        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let outputPath = outputDirectory.appendingPathComponent(outputFileName)
        let invocation = ProcessInvocation(
            executable: commandPath,
            arguments: [
                "xcresulttool",
                "get",
                "--legacy",
                "--format",
                "json",
                "--path",
                resultBundle.path
            ]
        )

        do {
            let result = try await processRunner.run(invocation)
            guard !result.standardOutput.isEmpty else {
                if result.isSuccess {
                    throw Error.missingRunnerOutput
                }
                throw Error.executionFailed("Process exited with non-zero status \(result.exitCode)")
            }
            try result.standardOutput.write(
                to: outputPath,
                atomically: true,
                encoding: .utf8
            )
            return outputPath
        } catch let error as ProcessRunnerError {
            throw Error.executionFailed("\(error)")
        }
    }
}
