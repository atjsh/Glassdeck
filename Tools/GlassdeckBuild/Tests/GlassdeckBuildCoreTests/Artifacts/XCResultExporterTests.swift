import Foundation
import XCTest
@testable import GlassdeckBuildCore

private func makeDefaultDiagnosticsOutput(_ outputDirectory: URL) throws {
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    let appLog = outputDirectory.appendingPathComponent(
        "StandardOutputAndStandardError-com.atjsh.GlassdeckDev.txt"
    )
    try "app stdout\napp stderr\n".write(to: appLog, atomically: true, encoding: .utf8)
}

private func makeDefaultAttachmentsOutput(_ outputDirectory: URL) throws {
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    let recording = outputDirectory.appendingPathComponent("screen-recording.mp4")
    FileManager.default.createFile(
        atPath: recording.path,
        contents: Data("recording".utf8),
        attributes: nil
    )
    let manifest = """
    [
      {
        "attachments": [
          {
            "exportedFileName": "screen-recording.mp4",
            "suggestedHumanReadableName": "Screen Recording"
          }
        ]
      }
    ]
    """
    try manifest.write(
        to: outputDirectory.appendingPathComponent("manifest.json"),
        atomically: true,
        encoding: .utf8
    )
}

private final class XCResultToolStubProcessRunner: ProcessRunner {
    let summaryOutput: String
    let failingSubcommands: Set<String>
    let diagnosticsOutput: @Sendable (URL) throws -> Void
    let attachmentsOutput: @Sendable (URL) throws -> Void
    private(set) var invocations: [ProcessInvocation] = []

    init(
        summaryOutput: String,
        failingSubcommands: Set<String> = [],
        diagnosticsOutput: @escaping @Sendable (URL) throws -> Void = makeDefaultDiagnosticsOutput,
        attachmentsOutput: @escaping @Sendable (URL) throws -> Void = makeDefaultAttachmentsOutput
    ) {
        self.summaryOutput = summaryOutput
        self.failingSubcommands = failingSubcommands
        self.diagnosticsOutput = diagnosticsOutput
        self.attachmentsOutput = attachmentsOutput
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessResult {
        invocations.append(invocation)
        XCTAssertEqual(invocation.executable, "/usr/bin/xcrun")
        XCTAssertEqual(invocation.arguments.first, "xcresulttool")

        if invocation.arguments.starts(with: ["xcresulttool", "get"]) {
            return ProcessResult(exitCode: 0, standardOutput: summaryOutput, standardError: "")
        }

        if invocation.arguments.starts(with: ["xcresulttool", "export", "diagnostics"]) {
            return try handleDirectoryExport(
                invocation: invocation,
                subcommand: "diagnostics",
                populate: diagnosticsOutput
            )
        }

        if invocation.arguments.starts(with: ["xcresulttool", "export", "attachments"]) {
            return try handleDirectoryExport(
                invocation: invocation,
                subcommand: "attachments",
                populate: attachmentsOutput
            )
        }

        XCTFail("Unexpected invocation: \(invocation.arguments)")
        return ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }

    private func handleDirectoryExport(
        invocation: ProcessInvocation,
        subcommand: String,
        populate: (URL) throws -> Void
    ) throws -> ProcessResult {
        if failingSubcommands.contains(subcommand) {
            throw ProcessRunnerError.nonzeroExit(
                ProcessResult(exitCode: 1, standardOutput: "", standardError: "\(subcommand) failed")
            )
        }

        let arguments = invocation.arguments
        guard let outputIndex = arguments.firstIndex(of: "--output-path"),
              arguments.indices.contains(outputIndex + 1) else {
            XCTFail("Missing output path for \(subcommand)")
            return ProcessResult(exitCode: 1, standardOutput: "", standardError: "")
        }
        let outputDirectory = URL(fileURLWithPath: arguments[outputIndex + 1])
        try populate(outputDirectory)
        return ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

final class XCResultExporterTests: XCTestCase {
    func testExportWritesStableArtifactsAndAliasesForUiTreeScreenAndTerminal() async throws {
        let tempRoot = try makeExporterTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundle = tempRoot.appendingPathComponent("result.xcresult")
        FileManager.default.createFile(atPath: bundle.path, contents: Data(), attributes: nil)
        let outputRoot = tempRoot.appendingPathComponent("artifacts")

        let runner = XCResultToolStubProcessRunner(
            summaryOutput: "{ \"format\": \"json\" }",
            diagnosticsOutput: { outputDirectory in
                try FileManager.default.createDirectory(
                    at: outputDirectory,
                    withIntermediateDirectories: true
                )
                let appLog = outputDirectory.appendingPathComponent(
                    "StandardOutputAndStandardError-com.atjsh.GlassdeckDev.txt"
                )
                try "app stdout\napp stderr\n".write(to: appLog, atomically: true, encoding: .utf8)
                let uiTree = outputDirectory.appendingPathComponent("ui-tree-3f2a.txt")
                try "ui tree body".write(to: uiTree, atomically: true, encoding: .utf8)
            },
            attachmentsOutput: { outputDirectory in
                try FileManager.default.createDirectory(
                    at: outputDirectory,
                    withIntermediateDirectories: true
                )
                let screen = outputDirectory.appendingPathComponent("screen-shot.png")
                FileManager.default.createFile(
                    atPath: screen.path,
                    contents: Data("screen".utf8),
                    attributes: nil
                )
                let terminal = outputDirectory.appendingPathComponent("terminal-output.png")
                FileManager.default.createFile(
                    atPath: terminal.path,
                    contents: Data("terminal".utf8),
                    attributes: nil
                )
                let recording = outputDirectory.appendingPathComponent("screen-recording.mp4")
                FileManager.default.createFile(
                    atPath: recording.path,
                    contents: Data("recording".utf8),
                    attributes: nil
                )
                let manifest = """
                [
                  {
                    "attachments": [
                      {
                        "exportedFileName": "screen-shot.png",
                        "suggestedHumanReadableName": "Screen"
                      },
                      {
                        "exportedFileName": "terminal-output.png",
                        "suggestedHumanReadableName": "Terminal"
                      },
                      {
                        "exportedFileName": "screen-recording.mp4",
                        "suggestedHumanReadableName": "Screen Recording"
                      }
                    ]
                  }
                ]
                """
                try manifest.write(
                    to: outputDirectory.appendingPathComponent("manifest.json"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        )
        let exporter = XCResultExporter(processRunner: runner)
        let result = try await exporter.export(resultBundle: bundle, outputDirectory: outputRoot)
        let layout = ArtifactLayout(artifactRoot: outputRoot)

        XCTAssertEqual(
            Set(result.entries.map { $0.path }),
            Set([
                ArtifactLayout.summaryJSONFileName,
                ArtifactLayout.diagnosticsDirectoryName,
                ArtifactLayout.appStdoutStderrFileName,
                ArtifactLayout.attachmentsDirectoryName,
                ArtifactLayout.recordingFileName,
                ArtifactLayout.screenFileName,
                ArtifactLayout.terminalFileName,
                ArtifactLayout.uiTreeFileName,
            ])
        )
        XCTAssertEqual(result.anomalies, [])
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: layout.screen.path))
                .standardizedFileURL
                .path,
            layout.attachmentsDirectory
                .appendingPathComponent("screen-shot.png")
                .standardizedFileURL
                .path
        )
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: layout.terminal.path))
                .standardizedFileURL
                .path,
            layout.attachmentsDirectory
                .appendingPathComponent("terminal-output.png")
                .standardizedFileURL
                .path
        )
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: layout.uiTree.path))
                .standardizedFileURL
                .path,
            layout.diagnosticsDirectory
                .appendingPathComponent("ui-tree-3f2a.txt")
                .standardizedFileURL
                .path
        )
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: layout.recording.path))
                .standardizedFileURL
                .path,
            layout.attachmentsDirectory
                .appendingPathComponent("screen-recording.mp4")
                .standardizedFileURL
                .path
        )
    }

    func testExportWritesStableArtifactsAndAliasesOptionalOutputs() async throws {
        let tempRoot = try makeExporterTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundle = tempRoot.appendingPathComponent("result.xcresult")
        FileManager.default.createFile(atPath: bundle.path, contents: Data(), attributes: nil)
        let outputRoot = tempRoot.appendingPathComponent("artifacts")

        let runner = XCResultToolStubProcessRunner(summaryOutput: "{ \"format\": \"json\" }")
        let exporter = XCResultExporter(processRunner: runner)
        let result = try await exporter.export(resultBundle: bundle, outputDirectory: outputRoot)
        let layout = ArtifactLayout(artifactRoot: outputRoot)

        XCTAssertEqual(result.entries.map(\.path), [
            ArtifactLayout.summaryJSONFileName,
            ArtifactLayout.diagnosticsDirectoryName,
            ArtifactLayout.appStdoutStderrFileName,
            ArtifactLayout.attachmentsDirectoryName,
            ArtifactLayout.recordingFileName,
        ])
        XCTAssertEqual(result.anomalies, [])
        XCTAssertEqual(
            try String(contentsOf: layout.summaryJSON, encoding: .utf8),
            "{ \"format\": \"json\" }"
        )
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: layout.appStdoutStderr.path))
                .standardizedFileURL
                .path,
            layout.diagnosticsDirectory
                .appendingPathComponent("StandardOutputAndStandardError-com.atjsh.GlassdeckDev.txt")
                .standardizedFileURL
                .path
        )
        XCTAssertEqual(
            URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: layout.recording.path))
                .standardizedFileURL
                .path,
            layout.attachmentsDirectory
                .appendingPathComponent("screen-recording.mp4")
                .standardizedFileURL
                .path
        )
    }

    func testExportRecordsOptionalExportAnomaliesButStillWritesSummaryJSON() async throws {
        let tempRoot = try makeExporterTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundle = tempRoot.appendingPathComponent("result.xcresult")
        FileManager.default.createFile(atPath: bundle.path, contents: Data(), attributes: nil)
        let outputRoot = tempRoot.appendingPathComponent("artifacts")

        let runner = XCResultToolStubProcessRunner(
            summaryOutput: "",
            failingSubcommands: ["diagnostics", "attachments"]
        )
        let exporter = XCResultExporter(processRunner: runner)
        let result = try await exporter.export(resultBundle: bundle, outputDirectory: outputRoot)

        XCTAssertEqual(result.entries.map(\.path), [ArtifactLayout.summaryJSONFileName])
        XCTAssertEqual(result.anomalies, [
            "xcresult-summary-empty",
            "xcresult-diagnostics-export-failed: exit-code=1",
            "xcresult-attachments-export-failed: exit-code=1",
        ])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputRoot.appendingPathComponent(ArtifactLayout.summaryJSONFileName).path
            )
        )
    }

    func testExportFailsWhenResultBundleMissing() async {
        let tempRoot = try! makeExporterTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let exporter = XCResultExporter(processRunner: XCResultToolStubProcessRunner(summaryOutput: "{}"))

        do {
            _ = try await exporter.export(
                resultBundle: tempRoot.appendingPathComponent("missing.xcresult"),
                outputDirectory: tempRoot
            )
            XCTFail("Expected export to throw")
        } catch {
            XCTAssertTrue(error is XCResultExporter.Error)
        }
    }
}

private func makeExporterTempRoot() throws -> URL {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("gb-export-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    return tempRoot
}
