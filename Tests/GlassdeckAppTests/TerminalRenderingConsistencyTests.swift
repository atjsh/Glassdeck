import UIKit
@testable import Glassdeck
import GlassdeckCore
import XCTest

/// Verifies that GhosttyKit surface creation and layout succeed for various configurations.
/// The pixel-level rendering consistency tests from the old CPU renderer are no longer
/// applicable; GhosttyKit uses its own GPU-accelerated rendering pipeline.
@MainActor
final class TerminalRenderingConsistencyTests: XCTestCase {

    func testSurfaceCreationIsCoveredByUITestAndHostIntegrationHarnesses() throws {
        throw XCTSkip(
            "Surface-owning terminal construction is validated in the UI and host integration harnesses; " +
            "the simulator-backed unit-test host still tears down CAMetalLayer-backed terminal views unreliably."
        )
    }

    func testGhosttyKitSurfaceIOEmitsSyntheticInputToOutputHandler() async throws {
        let io = GhosttyKitSurfaceIO()
        let recorder = InputRecorder()
        await io.setOutputHandler { data in
            Task { await recorder.append(data) }
        }

        io.emitInput(Data("pwd\u{7f}".utf8))
        try await Task.sleep(for: .milliseconds(100))

        let output = await recorder.outputData
        XCTAssertEqual(Array(output), Array(Data("pwd\u{7f}".utf8)))
    }

    func testPreviewBoundsCalculationReturnsValidSize() {
        let config = TerminalConfiguration(fontSize: 14)
        let bounds = GhosttySurface.previewBounds(
            for: TerminalSize(columns: 80, rows: 24),
            configuration: config
        )

        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
    }

    func testLayoutMetricsCellSizeIsPositive() {
        let config = TerminalConfiguration(fontSize: 14)
        let cellSize = GhosttySurfaceLayoutMetrics.cellSize(
            for: config,
            mode: .standard,
            metricsPreset: nil
        )

        XCTAssertGreaterThan(cellSize.width, 0)
        XCTAssertGreaterThan(cellSize.height, 0)
    }
}

private actor InputRecorder {
    private var chunks: [Data] = []

    func append(_ data: Data) {
        chunks.append(data)
    }

    var outputData: Data {
        chunks.reduce(into: Data(), { $0.append($1) })
    }
}
