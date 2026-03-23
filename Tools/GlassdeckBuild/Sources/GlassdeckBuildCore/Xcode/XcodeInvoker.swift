import Foundation

public struct XcodeCommandRequest: Sendable {
    public let action: XcodeAction
    public let scheme: SchemeSelector
    public let configuration: String?
    public let simulatorIdentifier: String?
    public let additionalArguments: [String]
    public let environmentAssignments: [String: String]

    public init(
        action: XcodeAction,
        scheme: SchemeSelector,
        configuration: String? = nil,
        simulatorIdentifier: String? = nil,
        additionalArguments: [String] = [],
        environmentAssignments: [String: String] = [:]
    ) {
        self.action = action
        self.scheme = scheme
        self.configuration = configuration
        self.simulatorIdentifier = simulatorIdentifier
        self.additionalArguments = additionalArguments
        self.environmentAssignments = environmentAssignments
    }
}

public struct XcodeRunResult: Sendable {
    public let request: XcodeCommandRequest
    public let invocation: ProcessInvocation
    public let processResult: ProcessResult
    public let paths: CommandArtifactPaths
    public let summaryPath: URL
    public let indexPath: URL
    public let xcresultExport: XCResultExportResult?
}

public enum XcodeInvokerError: Error, LocalizedError {
    case invocationFailed(ProcessInvocation, URL)

    public var errorDescription: String? {
        switch self {
        case let .invocationFailed(invocation, logPath):
            return "xcodebuild command failed: \(CommandLineRendering.render(invocation))\nLog: \(logPath.path)"
        }
    }
}

public final class XcodeInvoker {
    public let projectContext: XcodeProjectContext
    public let processRunner: ProcessRunner
    public let artifactPaths: ArtifactPaths
    public let manifestWriter: ArtifactManifestWriter
    public let xcresultExporter: XCResultExporting
    public let derivedDataManager: DerivedDataManager
    public let resultBundleLocator: ResultBundleLocator
    public let fileManager: FileManager
    public let nowProvider: @Sendable () -> Date
    public let xcodebuildExecutable: String
    public let outputMode: ProcessOutputMode
    public let retainedOutputByteLimit: Int?

    public init(
        projectContext: XcodeProjectContext,
        processRunner: ProcessRunner = DefaultProcessRunner(),
        artifactPaths: ArtifactPaths,
        manifestWriter: ArtifactManifestWriter = ArtifactManifestWriter(),
        xcresultExporter: XCResultExporting = XCResultExporter(),
        derivedDataManager: DerivedDataManager = DerivedDataManager(),
        resultBundleLocator: ResultBundleLocator = ResultBundleLocator(),
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        xcodebuildExecutable: String = "/usr/bin/xcodebuild",
        outputMode: ProcessOutputMode = .captureAndStreamTimestampedFiltered(.xcodebuild),
        retainedOutputByteLimit: Int? = 64 * 1024
    ) {
        self.projectContext = projectContext
        self.processRunner = processRunner
        self.artifactPaths = artifactPaths
        self.manifestWriter = manifestWriter
        self.xcresultExporter = xcresultExporter
        self.derivedDataManager = derivedDataManager
        self.resultBundleLocator = resultBundleLocator
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.xcodebuildExecutable = xcodebuildExecutable
        self.outputMode = outputMode
        self.retainedOutputByteLimit = retainedOutputByteLimit
    }

    public func makeInvocation(
        for request: XcodeCommandRequest,
        resultBundlePath: URL,
        capturedStandardOutputPath: URL? = nil,
        capturedStandardErrorPath: URL? = nil,
        retainedOutputByteLimit: Int? = nil
    ) -> ProcessInvocation {
        let configuration = request.configuration ?? projectContext.defaultConfiguration
        var arguments: [String] = [
            request.action.xcodebuildArgument,
            "-project", projectContext.projectPath.path,
            "-scheme", projectContext.scheme(for: request.scheme),
            "-configuration", configuration,
            "-destination", projectContext.destinationSpecifier(simulatorIdentifier: request.simulatorIdentifier),
            "-derivedDataPath", artifactPaths.derivedDataRoot.path,
            "-resultBundlePath", resultBundlePath.path,
        ]
        arguments.append(contentsOf: request.environmentAssignments
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" })
        arguments.append(contentsOf: request.additionalArguments)
        return ProcessInvocation(
            executable: xcodebuildExecutable,
            arguments: arguments,
            workingDirectory: projectContext.workspace.projectRoot,
            capturedStandardOutputPath: capturedStandardOutputPath,
            capturedStandardErrorPath: capturedStandardErrorPath,
            retainedOutputByteLimit: retainedOutputByteLimit,
            outputMode: outputMode
        )
    }

    public func execute(_ request: XcodeCommandRequest) async throws -> XcodeRunResult {
        try artifactPaths.ensureDirectoryLayout()
        try artifactPaths.ensureCommandRoots(for: request.action.artifactCommand)
        try derivedDataManager.prepare(at: artifactPaths.derivedDataRoot)

        let run = artifactPaths.makeRun(
            command: request.action.artifactCommand,
            runId: request.scheme.artifactRunID
        )
        let paths = artifactPaths.paths(for: run)

        try ensureParentDirectory(for: paths.resultBundle)
        try ensureParentDirectory(for: paths.resultLog)
        try ensureDirectory(paths.artifactRoot)

        let capturedStandardOutputPath = paths.artifactRoot.appendingPathComponent(".xcodebuild-stdout.log")
        let capturedStandardErrorPath = paths.artifactRoot.appendingPathComponent(".xcodebuild-stderr.log")
        let invocation = makeInvocation(
            for: request,
            resultBundlePath: paths.resultBundle,
            capturedStandardOutputPath: capturedStandardOutputPath,
            capturedStandardErrorPath: capturedStandardErrorPath,
            retainedOutputByteLimit: retainedOutputByteLimit
        )
        defer {
            try? removeItemIfExists(at: capturedStandardOutputPath)
            try? removeItemIfExists(at: capturedStandardErrorPath)
        }
        let outcome = await runProcessCapturingFailure(invocation)
        let processResult = outcome.result

        try writeLog(
            standardOutputPath: capturedStandardOutputPath,
            standardErrorPath: capturedStandardErrorPath,
            fallbackResult: processResult,
            to: paths.resultLog
        )

        try makeSymlink(from: paths.layout.log, to: paths.resultLog)

        var xcresultExport: XCResultExportResult?
        var summaryAnomalies: [String] = []

        if fileManager.fileExists(atPath: paths.resultBundle.path) {
            try makeSymlink(from: paths.layout.resultBundle, to: paths.resultBundle)

            do {
                let resolvedBundle = try resultBundleLocator.resolve(preferredPath: paths.resultBundle)
                let exportResult = try await xcresultExporter.export(
                    resultBundle: resolvedBundle,
                    outputDirectory: paths.artifactRoot
                )
                xcresultExport = exportResult
                summaryAnomalies.append(contentsOf: exportResult.anomalies)
            } catch {
                summaryAnomalies.append("xcresult-export-failed: \(error)")
            }
        } else {
            summaryAnomalies.append("missing-result-bundle")
        }

        let summaryLines = buildSummaryLines(
            request: request,
            invocation: invocation,
            processResult: processResult,
            logPath: paths.resultLog,
            anomalies: summaryAnomalies
        )
        let summaryPath = try manifestWriter.writeSummary(summaryLines, to: paths.artifactRoot)

        var indexBuilder = ArtifactIndexBuilder(
            command: request.action.artifactCommand,
            worker: artifactPaths.worker,
            run: run,
            startedAt: nowProvider(),
            clock: nowProvider
        )
        indexBuilder.record(
            phase: "01-command",
            kind: "log",
            relativePath: paths.layout.relativePath(for: paths.layout.log)
        )
        if fileManager.fileExists(atPath: paths.resultBundle.path) {
            indexBuilder.record(
                phase: "02-result-bundle",
                kind: "xcresult",
                relativePath: paths.layout.relativePath(for: paths.layout.resultBundle)
            )
        }
        if let xcresultExport {
            indexBuilder.merge(xcresultExport.entries)
        }
        indexBuilder.record(
            phase: "99-summary",
            kind: "text",
            relativePath: paths.layout.relativePath(for: summaryPath),
            anomaly: summaryAnomalies.isEmpty ? nil : summaryAnomalies.joined(separator: ", ")
        )
        let indexPath = try manifestWriter.write(
            indexBuilder.build(completedAt: nowProvider()),
            to: paths.artifactRoot
        )

        try artifactPaths.updateLatestAlias(for: run)

        if outcome.failed {
            throw XcodeInvokerError.invocationFailed(invocation, paths.resultLog)
        }

        return XcodeRunResult(
            request: request,
            invocation: invocation,
            processResult: processResult,
            paths: paths,
            summaryPath: summaryPath,
            indexPath: indexPath,
            xcresultExport: xcresultExport
        )
    }

    private func runProcessCapturingFailure(_ invocation: ProcessInvocation) async -> (result: ProcessResult, failed: Bool) {
        do {
            let result = try await processRunner.run(invocation)
            return (result, false)
        } catch let ProcessRunnerError.nonzeroExit(result) {
            return (result, true)
        } catch {
            return (
                ProcessResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "\(error)"
                ),
                true
            )
        }
    }

    private func writeLog(
        standardOutputPath: URL,
        standardErrorPath: URL,
        fallbackResult: ProcessResult,
        to destination: URL
    ) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer { destinationHandle.closeFile() }

        destinationHandle.write(Data("[stdout]\n".utf8))
        try appendLogContents(
            from: standardOutputPath,
            fallback: fallbackResult.standardOutput,
            to: destinationHandle
        )
        destinationHandle.write(Data("\n[stderr]\n".utf8))
        try appendLogContents(
            from: standardErrorPath,
            fallback: fallbackResult.standardError,
            to: destinationHandle
        )
    }

    private func appendLogContents(
        from source: URL,
        fallback: String,
        to destinationHandle: FileHandle
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            destinationHandle.write(Data(fallback.utf8))
            return
        }

        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { sourceHandle.closeFile() }

        while true {
            let chunk = sourceHandle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty {
                return
            }
            destinationHandle.write(chunk)
        }
    }

    private func buildSummaryLines(
        request: XcodeCommandRequest,
        invocation: ProcessInvocation,
        processResult: ProcessResult,
        logPath: URL,
        anomalies: [String]
    ) -> [String] {
        var lines: [String] = [
            "action: \(request.action.rawValue)",
            "scheme: \(request.scheme.schemeName)",
            "exit-code: \(processResult.exitCode)",
            "command: \(CommandLineRendering.render(invocation))",
            "log: \(logPath.path)",
        ]
        if !anomalies.isEmpty {
            lines.append("anomalies: \(anomalies.joined(separator: ", "))")
        }
        if !processResult.standardError.isEmpty {
            lines.append("")
            lines.append("[stderr]")
            lines.append(processResult.standardError)
        }
        if !processResult.standardOutput.isEmpty {
            lines.append("")
            lines.append("[stdout]")
            lines.append(processResult.standardOutput)
        }
        return lines
    }

    private func ensureParentDirectory(for path: URL) throws {
        try ensureDirectory(path.deletingLastPathComponent())
    }

    private func ensureDirectory(_ path: URL) throws {
        if !fileManager.fileExists(atPath: path.path) {
            try fileManager.createDirectory(
                at: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func makeSymlink(from destination: URL, to source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func removeItemIfExists(at path: URL) throws {
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }
}
