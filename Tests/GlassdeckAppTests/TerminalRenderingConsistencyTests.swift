import UIKit
@testable import Glassdeck
import GlassdeckCore
import XCTest

/// Verifies that GhosttyKit surface creation and layout succeed for various configurations.
/// The pixel-level rendering consistency tests from the old CPU renderer are no longer
/// applicable; GhosttyKit uses its own GPU-accelerated rendering pipeline.
@MainActor
final class TerminalRenderingConsistencyTests: XCTestCase {

    func testSurfaceCreationSucceedsWithVariousFontSizes() throws {
        for fontSize in [12.0, 13.0, 14.0, 16.0] {
            let config = TerminalConfiguration(fontSize: fontSize, scrollbackLines: 0, cursorBlink: false)
            let surface = try GhosttySurface(configuration: config)
            XCTAssertNotNil(surface, "Surface creation should succeed at \(fontSize)pt")
        }
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
