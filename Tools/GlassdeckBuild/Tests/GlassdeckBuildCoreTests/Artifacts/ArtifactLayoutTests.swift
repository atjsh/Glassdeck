import Foundation
import XCTest
@testable import GlassdeckBuildCore

final class ArtifactLayoutTests: XCTestCase {
    func testStableInspectionPathsUseExpectedNames() {
        let root = URL(fileURLWithPath: "/tmp/artifacts/run-1")
        let layout = ArtifactLayout(artifactRoot: root)

        XCTAssertEqual(layout.stableInspectionPaths.map(\.lastPathComponent), [
            ArtifactLayout.logFileName,
            ArtifactLayout.resultBundleFileName,
            ArtifactLayout.summaryJSONFileName,
            ArtifactLayout.summaryFileName,
            ArtifactLayout.indexFileName,
            ArtifactLayout.diagnosticsDirectoryName,
            ArtifactLayout.attachmentsDirectoryName,
            ArtifactLayout.appStdoutStderrFileName,
            ArtifactLayout.recordingFileName,
            ArtifactLayout.screenFileName,
            ArtifactLayout.terminalFileName,
            ArtifactLayout.uiTreeFileName,
        ])
    }

    func testRelativePathUsesArtifactRootWhenPossible() {
        let root = URL(fileURLWithPath: "/tmp/artifacts/run-1")
        let layout = ArtifactLayout(artifactRoot: root)

        XCTAssertEqual(layout.relativePath(for: layout.summary), ArtifactLayout.summaryFileName)
        XCTAssertEqual(
            layout.relativePath(for: layout.diagnosticsDirectory.appendingPathComponent("trace.txt")),
            "\(ArtifactLayout.diagnosticsDirectoryName)/trace.txt"
        )
        XCTAssertEqual(
            layout.relativePath(for: URL(fileURLWithPath: "/tmp/elsewhere/recording.mp4")),
            "recording.mp4"
        )
    }
}
