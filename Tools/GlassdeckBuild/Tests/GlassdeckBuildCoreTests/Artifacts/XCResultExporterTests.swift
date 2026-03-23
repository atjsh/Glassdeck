import Foundation
import XCTest
@testable import GlassdeckBuildCore

private final class MockProcessRunner: ProcessRunner {
    let output: String
    let exitCode: Int

    init(output: String, exitCode: Int = 0) {
        self.output = output
        self.exitCode = exitCode
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessResult {
        XCTAssertEqual(invocation.executable, "/usr/bin/xcrun")
        XCTAssertEqual(invocation.arguments.first, "xcresulttool")
        XCTAssertTrue(invocation.arguments.contains("--legacy"))
        return ProcessResult(
            exitCode: exitCode,
            standardOutput: output,
            standardError: ""
        )
    }
}

private final class FailingProcessRunner: ProcessRunner {
    func run(_ invocation: ProcessInvocation) async throws -> ProcessResult {
        throw ProcessRunnerError.nonzeroExit(ProcessResult(exitCode: 1, standardOutput: "", standardError: "boom"))
    }
}

final class XCResultExporterTests: XCTestCase {
    func testExportUsesProcessOutputToCreateSummary() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-export-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let bundle = tempRoot.appendingPathComponent("result.xcresult")
        FileManager.default.createFile(atPath: bundle.path, contents: Data(), attributes: nil)
        let outputRoot = tempRoot.appendingPathComponent("artifacts")

        let runner = MockProcessRunner(output: "{ \"format\": \"json\" }")
        let exporter = XCResultExporter(processRunner: runner)
        let exportedURL = try await exporter.export(resultBundle: bundle, outputDirectory: outputRoot)

        let exportedContent = try String(contentsOf: exportedURL, encoding: .utf8)
        XCTAssertEqual(exportedContent, "{ \"format\": \"json\" }")
        XCTAssertEqual(exportedURL.lastPathComponent, "summary.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
    }

    func testExportFailsWhenResultBundleMissing() async {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-export-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try! FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let exporter = XCResultExporter(processRunner: FailingProcessRunner())

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
