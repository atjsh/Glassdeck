import UIKit
@testable import Glassdeck
import GlassdeckCore
import XCTest

@MainActor
final class GhosttyHomeAnimationPerformanceTests: XCTestCase {
    func testHomeAnimationNormalizedPayloadPreservesBrandAccentAndGridDimensions() throws {
        let frameURL = try animationFixturesURL().appending(path: "frame_016.txt")
        let rawFrame = try String(contentsOf: frameURL, encoding: .utf8)
        let payload = try GhosttyHomeAnimationSequence.normalizedFramePayload(
            fromRawText: rawFrame,
            fileName: frameURL.lastPathComponent
        )
        let payloadString = String(decoding: payload, as: UTF8.self)

        XCTAssertTrue(
            payloadString.contains("\u{1B}[38;2;53;81;243m"),
            "Expected animation payload to contain the website brand-blue ANSI foreground color."
        )

        let stripped = payloadString.replacingOccurrences(
            of: #"\x{1B}\[[0-9;?]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
        let rows = stripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(
            rows.count,
            GhosttyHomeAnimationSequence.expectedRows,
            "Expected normalized animation payload to keep the website frame height."
        )
        XCTAssertTrue(
            rows.allSatisfy { $0.count == GhosttyHomeAnimationSequence.expectedColumns },
            "Expected normalized animation payload to keep the website frame width."
        )
    }

    func testHomeAnimationFrameProjectionContainsVisibleRowsAndDistinctDefaultColors() throws {
        let sequence = try GhosttyHomeAnimationSequence.load(from: animationFixturesURL())
        let engine = try GhosttyVTTerminalEngine(
            options: GhosttyVTTerminalOptions(
                columns: UInt16(GhosttyHomeAnimationSequence.expectedColumns),
                rows: UInt16(GhosttyHomeAnimationSequence.expectedRows),
                scrollbackLines: 0
            )
        )

        engine.write(sequence.frames[GhosttyHomeAnimationSequence.startFrameIndex].payload)
        let projection = try engine.snapshotProjection(clearDirty: true)

        XCTAssertNotEqual(
            projection.foregroundColor,
            projection.backgroundColor,
            "Expected Ghostty replay frames to resolve distinct default foreground and background colors."
        )
        XCTAssertTrue(
            projection.rowsProjection.contains { !visibleTextRow(from: $0).isEmpty },
            "Expected Ghostty replay frames to populate visible terminal rows."
        )
    }

    func testHomeAnimationReplayAverageFrameTimeStaysWithinBudget() throws {
        let sequence = try GhosttyHomeAnimationSequence.load(from: animationFixturesURL())
        let harness = try makeSurfaceHarness(for: sequence.terminalSize)
        defer { harness.window.isHidden = true }

        let player = GhosttyHomeAnimationPlayer(
            surface: harness.surface,
            sequence: sequence
        )

        _ = try player.replayLoop()
        let metrics = try player.replayLoop()

        XCTAssertNil(
            harness.surface.stateSnapshot.renderFailureReason,
            "Expected Ghostty home animation replay to remain renderable."
        )
        XCTAssertFalse(
            harness.surface.stateSnapshot.visibleTextSummary.isEmpty,
            "Expected Ghostty home animation replay to leave visible terminal text."
        )
        XCTAssertLessThanOrEqual(
            metrics.averageFrameDuration,
            performanceBudget,
            "Expected Ghostty home animation replay average frame time to stay within \(formattedMilliseconds(performanceBudget)) ms, but observed \(formattedMilliseconds(metrics.averageFrameDuration)) ms."
        )
    }

    func testHomeAnimationReplayProducesSoftwareMirrorImage() throws {
        let sequence = try GhosttyHomeAnimationSequence.load(from: animationFixturesURL())
        let harness = try makeSurfaceHarness(for: sequence.terminalSize)
        defer { harness.window.isHidden = true }

        let player = GhosttyHomeAnimationPlayer(
            surface: harness.surface,
            sequence: sequence
        )

        _ = try player.replayLoop()

        XCTAssertTrue(
            harness.surface.hasSoftwareMirrorImage,
            "Expected Ghostty home animation replay to produce a software-mirror image on simulator."
        )
    }

    func testTerminalLayoutMetricsKeepConfiguredFontSizeOnExternalDisplay() {
        let configuration = TerminalConfiguration(fontSize: 14)

        XCTAssertEqual(
            GhosttySurfaceLayoutMetrics.fontSize(for: configuration, mode: .externalDisplay),
            14,
            accuracy: 0.001
        )
    }

    func testTerminalLayoutMetricsPreserveWiderPaddingForExternalDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 1_280, height: 800)

        let standard = GhosttySurfaceLayoutMetrics.basePadding(
            for: bounds,
            mode: .standard,
            metricsPreset: nil
        )
        let external = GhosttySurfaceLayoutMetrics.basePadding(
            for: bounds,
            mode: .externalDisplay,
            metricsPreset: nil
        )

        XCTAssertGreaterThan(external.left, standard.left)
        XCTAssertGreaterThan(external.top, standard.top)
    }

    func testTerminalLayoutMetricsAnchorTextToCellLeadingEdge() {
        let cellRect = CGRect(x: 12, y: 24, width: 18, height: 30)
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        let textRect = GhosttySurfaceLayoutMetrics.textRect(for: cellRect, font: font)

        XCTAssertEqual(textRect.minX, cellRect.minX)
        XCTAssertLessThanOrEqual(textRect.maxX, cellRect.maxX)
    }

    private var performanceBudget: TimeInterval {
        #if targetEnvironment(simulator)
        0.022
        #else
        0.0167
        #endif
    }

    private func makeSurfaceHarness(
        for terminalSize: TerminalSize
    ) throws -> (window: UIWindow, surface: GhosttySurface) {
        let bounds = GhosttySurface.previewBounds(
            for: terminalSize,
            configuration: GhosttyHomeAnimationSequence.testingTerminalConfiguration,
            metricsPreset: GhosttyHomeAnimationSequence.testingMetricsPreset
        )
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached })
        else {
            XCTFail("Expected an attached UIWindowScene for Ghostty animation performance tests.")
            throw GhosttyVTError.unavailable
        }

        let window = UIWindow(windowScene: windowScene)
        window.frame = bounds
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.loadViewIfNeeded()
        viewController.view.frame = bounds

        let surface = try GhosttySurface(
            configuration: GhosttyHomeAnimationSequence.testingTerminalConfiguration,
            metricsPreset: GhosttyHomeAnimationSequence.testingMetricsPreset
        )
        surface.frame = viewController.view.bounds
        viewController.view.addSubview(surface)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        surface.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        return (window, surface)
    }

    private func animationFixturesURL(
        file: StaticString = #filePath
    ) throws -> URL {
        if let bundleURL = Bundle(for: Self.self).url(forResource: "GhosttyHomeAnimationFrames", withExtension: nil) {
            return bundleURL
        }

        let sourceURL = URL(fileURLWithPath: "\(file)")
        let fallbackURL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/GhosttyHomeAnimationFrames")

        guard FileManager.default.fileExists(atPath: fallbackURL.path) else {
            throw GhosttyHomeAnimationError.framesDirectoryMissing(fallbackURL.path)
        }

        return fallbackURL
    }

    private func formattedMilliseconds(_ duration: TimeInterval) -> String {
        String(format: "%.2f", duration * 1_000)
    }

    private func visibleTextRow(from row: GhosttyVTRowProjection) -> String {
        row.cells
            .sorted { $0.column < $1.column }
            .compactMap { cell -> String? in
                switch cell.width {
                case .spacerHead, .spacerTail:
                    nil
                case .narrow, .wide:
                    cell.text.isEmpty ? " " : cell.text
                }
            }
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}
