import Foundation
import XCTest
@testable import GlassdeckBuildCore

private final class RecordingXCResultExporter: XCResultExporting {
    let exportResult: XCResultExportResult
    let exportError: Error?
    private(set) var exportedBundles: [URL] = []

    init(exportResult: XCResultExportResult, exportError: Error? = nil) {
        self.exportResult = exportResult
        self.exportError = exportError
    }

    func export(resultBundle: URL, outputDirectory: URL) async throws -> XCResultExportResult {
        exportedBundles.append(resultBundle)
        if let exportError {
            throw exportError
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try "{}\n".write(
            to: outputDirectory.appendingPathComponent(ArtifactLayout.summaryJSONFileName),
            atomically: true,
            encoding: .utf8
        )
        return exportResult
    }
}

private func makeWorkspaceRoot() throws -> URL {
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("gb-xcode-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: workspaceRoot.appendingPathComponent("Glassdeck/GlassdeckApp.xcodeproj"),
        withIntermediateDirectories: true
    )
    return workspaceRoot
}

private func makeInvoker(
    artifactPaths: ArtifactPaths,
    processRunner: ProcessRunner,
    exporter: RecordingXCResultExporter,
    workspaceRoot: URL,
    nowProvider: @escaping @Sendable () -> Date
) -> XcodeInvoker {
    XcodeInvoker(
        projectContext: XcodeProjectContext(workspace: .init(workspaceRoot: workspaceRoot)),
        processRunner: processRunner,
        artifactPaths: artifactPaths,
        xcresultExporter: exporter,
        nowProvider: nowProvider
    )
}

final class XcodeInvokerTests: XCTestCase {
    func testInvocationIncludesDestinationDerivedDataAndResultBundle() {
        let workspace = WorkspaceContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws"),
            projectRootName: "Glassdeck"
        )
        let projectContext = XcodeProjectContext(workspace: workspace)
        let artifactPaths = ArtifactPaths(
            repoRoot: projectContext.workspace.projectRoot,
            worker: "worker-0"
        )
        let invoker = XcodeInvoker(
            projectContext: projectContext,
            artifactPaths: artifactPaths
        )

        let request = XcodeCommandRequest(
            action: .testWithoutBuilding,
            scheme: .ui,
            simulatorIdentifier: "SIM-1234",
            environmentAssignments: ["SIMCTL_CHILD_FOO": "BAR"]
        )
        let invocation = invoker.makeInvocation(
            for: request,
            resultBundlePath: URL(fileURLWithPath: "/tmp/out.xcresult")
        )

        XCTAssertEqual(invocation.executable, "/usr/bin/xcodebuild")
        XCTAssertTrue(invocation.arguments.contains("test-without-building"))
        XCTAssertTrue(invocation.arguments.contains("GlassdeckAppUI"))
        XCTAssertTrue(invocation.arguments.contains("platform=iOS Simulator,id=SIM-1234"))
        XCTAssertTrue(invocation.arguments.contains("/tmp/out.xcresult"))
        XCTAssertTrue(invocation.arguments.contains("SIMCTL_CHILD_FOO=BAR"))
        XCTAssertEqual(invocation.outputMode, .captureAndStreamTimestampedFiltered(.xcodebuild))
    }

    func testExecuteWritesMergedIndexEntriesAndUpdatesLatestAlias() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let fixedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let nowProvider: @Sendable () -> Date = { fixedDate }
        let artifactPaths = ArtifactPaths(
            repoRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            worker: "worker-0",
            nowProvider: nowProvider
        )
        let run = artifactPaths.makeRun(command: "test", runId: "ui", timestamp: artifactPaths.formatRunTimestamp(fixedDate))
        let paths = artifactPaths.paths(for: run)
        try FileManager.default.createDirectory(at: paths.artifactRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.resultBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.resultBundle.path, contents: Data(), attributes: nil)

        let exporter = RecordingXCResultExporter(
            exportResult: XCResultExportResult(
                entries: [
                    ArtifactIndexEntry(
                        phase: "03-summary-json",
                        kind: "json",
                        path: ArtifactLayout.summaryJSONFileName,
                        timestamp: fixedDate
                    ),
                    ArtifactIndexEntry(
                        phase: "04-diagnostics",
                        kind: "directory",
                        path: ArtifactLayout.diagnosticsDirectoryName,
                        timestamp: fixedDate
                    ),
                ]
            )
        )
        let invoker = makeInvoker(
            artifactPaths: artifactPaths,
            processRunner: ScriptedProcessRunner(
                responses: [
                    ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
                ]
            ),
            exporter: exporter,
            workspaceRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            nowProvider: nowProvider
        )

        let result = try await invoker.execute(
            XcodeCommandRequest(
                action: .testWithoutBuilding,
                scheme: .ui,
                simulatorIdentifier: "SIM-0001"
            )
        )

        let index = try ArtifactManifestWriter().readIndex(from: result.indexPath)
        XCTAssertEqual(index.command, "test")
        XCTAssertEqual(index.entries.map(\.path), [
            ArtifactLayout.logFileName,
            ArtifactLayout.resultBundleFileName,
            ArtifactLayout.summaryJSONFileName,
            ArtifactLayout.diagnosticsDirectoryName,
            ArtifactLayout.summaryFileName,
        ])
        XCTAssertNil(index.entries.last?.anomaly)

        let aliasURL = paths.artifactRoot
            .deletingLastPathComponent()
            .appendingPathComponent("latest")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: aliasURL.path)
        XCTAssertEqual(aliasURL.appendingPathComponent(destination).lastPathComponent, paths.artifactRoot.lastPathComponent)
    }

    func testExecuteMergesStableAliasEntriesForScreenTerminalAndUiTree() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let fixedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let nowProvider: @Sendable () -> Date = { fixedDate }
        let artifactPaths = ArtifactPaths(
            repoRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            worker: "worker-0",
            nowProvider: nowProvider
        )
        let run = artifactPaths.makeRun(command: "test", runId: "ui", timestamp: artifactPaths.formatRunTimestamp(fixedDate))
        let paths = artifactPaths.paths(for: run)
        try FileManager.default.createDirectory(at: paths.artifactRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.resultBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.resultBundle.path, contents: Data(), attributes: nil)

        let exporter = RecordingXCResultExporter(
            exportResult: XCResultExportResult(
                entries: [
                    ArtifactIndexEntry(
                        phase: "03-summary-json",
                        kind: "json",
                        path: ArtifactLayout.summaryJSONFileName,
                        timestamp: fixedDate
                    ),
                    ArtifactIndexEntry(
                        phase: "04-diagnostics",
                        kind: "directory",
                        path: ArtifactLayout.diagnosticsDirectoryName,
                        timestamp: fixedDate
                    ),
                    ArtifactIndexEntry(
                        phase: "05-app-stdout-stderr",
                        kind: "text",
                        path: ArtifactLayout.appStdoutStderrFileName,
                        timestamp: fixedDate
                    ),
                    ArtifactIndexEntry(
                        phase: "06-screen",
                        kind: "image",
                        path: ArtifactLayout.screenFileName,
                        timestamp: fixedDate
                    ),
                    ArtifactIndexEntry(
                        phase: "07-terminal",
                        kind: "image",
                        path: ArtifactLayout.terminalFileName,
                        timestamp: fixedDate
                    ),
                    ArtifactIndexEntry(
                        phase: "08-ui-tree",
                        kind: "text",
                        path: ArtifactLayout.uiTreeFileName,
                        timestamp: fixedDate
                    ),
                ]
            )
        )
        let invoker = makeInvoker(
            artifactPaths: artifactPaths,
            processRunner: ScriptedProcessRunner(
                responses: [
                    ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
                ]
            ),
            exporter: exporter,
            workspaceRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            nowProvider: nowProvider
        )

        let result = try await invoker.execute(
            XcodeCommandRequest(
                action: .testWithoutBuilding,
                scheme: .ui,
                simulatorIdentifier: "SIM-0001"
            )
        )

        let index = try ArtifactManifestWriter().readIndex(from: result.indexPath)
        XCTAssertEqual(index.entries.map(\.path), [
            ArtifactLayout.logFileName,
            ArtifactLayout.resultBundleFileName,
            ArtifactLayout.summaryJSONFileName,
            ArtifactLayout.diagnosticsDirectoryName,
            ArtifactLayout.appStdoutStderrFileName,
            ArtifactLayout.screenFileName,
            ArtifactLayout.terminalFileName,
            ArtifactLayout.uiTreeFileName,
            ArtifactLayout.summaryFileName,
        ])
    }

    func testExecutePropagatesExportAnomaliesIntoSummaryAndIndex() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let fixedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let nowProvider: @Sendable () -> Date = { fixedDate }
        let artifactPaths = ArtifactPaths(
            repoRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            nowProvider: nowProvider
        )
        let run = artifactPaths.makeRun(command: "test", runId: "ui", timestamp: artifactPaths.formatRunTimestamp(fixedDate))
        let paths = artifactPaths.paths(for: run)
        try FileManager.default.createDirectory(at: paths.artifactRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.resultBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.resultBundle.path, contents: Data(), attributes: nil)

        let anomaly = "xcresult-diagnostics-export-failed: exit-code=1"
        let exporter = RecordingXCResultExporter(
            exportResult: XCResultExportResult(
                entries: [
                    ArtifactIndexEntry(
                        phase: "03-summary-json",
                        kind: "json",
                        path: ArtifactLayout.summaryJSONFileName,
                        timestamp: fixedDate
                    ),
                ],
                anomalies: [anomaly]
            )
        )
        let invoker = makeInvoker(
            artifactPaths: artifactPaths,
            processRunner: ScriptedProcessRunner(
                responses: [
                    ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
                ]
            ),
            exporter: exporter,
            workspaceRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            nowProvider: nowProvider
        )

        let result = try await invoker.execute(
            XcodeCommandRequest(action: .test, scheme: .ui, simulatorIdentifier: "SIM-0001")
        )

        let summaryContent = try String(contentsOf: result.summaryPath, encoding: .utf8)
        XCTAssertTrue(summaryContent.contains("anomalies: \(anomaly)"))
        let index = try ArtifactManifestWriter().readIndex(from: result.indexPath)
        XCTAssertEqual(index.entries.last?.anomaly, anomaly)
    }

    func testExecuteExportsWhenXcodebuildFailsAndStillWritesSummaryAndIndex() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let fixedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let nowProvider: @Sendable () -> Date = { fixedDate }
        let artifactPaths = ArtifactPaths(
            repoRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            nowProvider: nowProvider
        )
        let run = artifactPaths.makeRun(command: "test", runId: "ui", timestamp: artifactPaths.formatRunTimestamp(fixedDate))
        let paths = artifactPaths.paths(for: run)
        try FileManager.default.createDirectory(at: paths.resultBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.artifactRoot, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.resultBundle.path, contents: Data(), attributes: nil)

        let exporter = RecordingXCResultExporter(
            exportResult: XCResultExportResult(
                entries: [
                    ArtifactIndexEntry(
                        phase: "03-summary-json",
                        kind: "json",
                        path: ArtifactLayout.summaryJSONFileName,
                        timestamp: fixedDate
                    )
                ]
            )
        )
        let invoker = makeInvoker(
            artifactPaths: artifactPaths,
            processRunner: ScriptedProcessRunner(
                responses: [
                    ScriptedResponse(
                        result: ProcessResult(
                            exitCode: 1,
                            standardOutput: "fail",
                            standardError: "oops"
                        ),
                        error: ProcessRunnerError.nonzeroExit(
                            ProcessResult(
                                exitCode: 1,
                                standardOutput: "fail",
                                standardError: "oops"
                            )
                        )
                    )
                ]
            ),
            exporter: exporter,
            workspaceRoot: workspaceRoot.appendingPathComponent("Glassdeck"),
            nowProvider: nowProvider
        )

        do {
            _ = try await invoker.execute(
                XcodeCommandRequest(action: .test, scheme: .ui, simulatorIdentifier: "SIM-0001")
            )
            XCTFail("Expected non-zero xcodebuild execution to fail")
        } catch let error as XcodeInvokerError {
            switch error {
            case let .invocationFailed(_, logPath):
                XCTAssertEqual(logPath, paths.resultLog)
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.summary.path))
        XCTAssertEqual(exporter.exportedBundles.count, 1)
        let index = try ArtifactManifestWriter().readIndex(
            from: paths.artifactRoot.appendingPathComponent(ArtifactLayout.indexFileName)
        )
        XCTAssertEqual(index.entries.map(\.path), [
            ArtifactLayout.logFileName,
            ArtifactLayout.resultBundleFileName,
            ArtifactLayout.summaryJSONFileName,
            ArtifactLayout.summaryFileName,
        ])
    }
}
