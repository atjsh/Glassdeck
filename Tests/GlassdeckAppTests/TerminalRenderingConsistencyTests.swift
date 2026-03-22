import UIKit
@testable import Glassdeck
import GlassdeckCore
import XCTest

/// Verifies that narrow (English) characters render identically regardless of whether the
/// row also contains wide (Korean/CJK) characters. The terminal uses two drawing paths
/// internally; this test ensures they produce matching pixel output.
@MainActor
final class TerminalRenderingConsistencyTests: XCTestCase {

    // MARK: - Rendering Consistency

    func testEnglishGlyphsRenderIdenticallyOnPureAndMixedRows() throws {
        // Row 0: English only (triggers optimised whole-row path)
        // Row 1: English + Korean (forces cell-by-cell path for all cells)
        let image = try renderTerminalContent(
            rows: ["Hello World", "Hello \u{C548}\u{B155}"],  // "Hello 안녕"
            fontSize: 14
        )
        let cgImage = try XCTUnwrap(image.cgImage)

        let cellSize = terminalCellSize(fontSize: 14)
        let padding = terminalPadding(imageSize: image.size, columns: 80, rows: 24, cellSize: cellSize)

        // Compare "Hello " (columns 0–5) on row 0 vs row 1
        let row0Pixels = extractPixels(
            from: cgImage,
            row: 0, startCol: 0, endCol: 6,
            cellSize: cellSize, padding: padding, scale: image.scale
        )
        let row1Pixels = extractPixels(
            from: cgImage,
            row: 1, startCol: 0, endCol: 6,
            cellSize: cellSize, padding: padding, scale: image.scale
        )

        let matchRate = pixelMatchRate(row0Pixels, row1Pixels, tolerance: 5)
        XCTAssertGreaterThanOrEqual(
            matchRate, 0.82,
            "English glyphs must render identically (≥82% match) on pure-English and mixed rows. Got \(String(format: "%.1f%%", matchRate * 100))"
        )
    }

    func testEnglishGlyphConsistencyAcrossFontSizes() throws {
        for fontSize in [12.0, 13.0, 14.0, 16.0] {
            let image = try renderTerminalContent(
                rows: ["ABCDEFGHIJ", "ABCDE\u{D55C}\u{AE00}"],  // "ABCDE한글"
                fontSize: fontSize
            )
            let cgImage = try XCTUnwrap(image.cgImage)

            let cellSize = terminalCellSize(fontSize: fontSize)
            let padding = terminalPadding(imageSize: image.size, columns: 80, rows: 24, cellSize: cellSize)

            let row0Pixels = extractPixels(
                from: cgImage,
                row: 0, startCol: 0, endCol: 5,
                cellSize: cellSize, padding: padding, scale: image.scale
            )
            let row1Pixels = extractPixels(
                from: cgImage,
                row: 1, startCol: 0, endCol: 5,
                cellSize: cellSize, padding: padding, scale: image.scale
            )

            let matchRate = pixelMatchRate(row0Pixels, row1Pixels, tolerance: 5)
            XCTAssertGreaterThanOrEqual(
                matchRate, 0.82,
                "English glyphs must match at \(fontSize)pt. Got \(String(format: "%.1f%%", matchRate * 100))"
            )
        }
    }

    // MARK: - Helpers

    private func renderTerminalContent(
        rows: [String],
        fontSize: Double,
        columns: Int = 80,
        terminalRows: Int = 24
    ) throws -> UIImage {
        let config = TerminalConfiguration(fontSize: fontSize, scrollbackLines: 0, cursorBlink: false)
        let surface = try GhosttySurface(configuration: config)

        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached })
        else {
            throw XCTestError(.failureWhileWaiting)
        }

        let bounds = GhosttySurface.previewBounds(
            for: TerminalSize(columns: columns, rows: terminalRows),
            configuration: config
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = bounds
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        vc.view.frame = bounds

        surface.frame = vc.view.bounds
        vc.view.addSubview(surface)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        surface.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        // Write content: position cursor per row, then write text
        for (index, text) in rows.enumerated() {
            // Move cursor to row (1-indexed) and write text
            let ansi = "\u{1B}[\(index + 1);1H\(text)"
            surface.engine.write(Data(ansi.utf8))
        }

        // Trigger layout which calls render internally (synchronous on simulator)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        // On simulator, the software mirror UIImageView holds the rendered frame directly.
        // Using it avoids resampling artifacts introduced by drawHierarchy.
        let mirrorImageView = surface.subviews.compactMap { $0 as? UIImageView }.first
        let renderedImage = try XCTUnwrap(mirrorImageView?.image, "Software mirror image not available")

        window.isHidden = true
        return renderedImage
    }

    private func terminalCellSize(fontSize: Double) -> CGSize {
        GhosttySurfaceLayoutMetrics.cellSize(
            for: TerminalConfiguration(fontSize: fontSize),
            mode: .standard,
            metricsPreset: nil
        )
    }

    private func terminalPadding(
        imageSize: CGSize,
        columns: Int,
        rows: Int,
        cellSize: CGSize
    ) -> UIEdgeInsets {
        let contentWidth = CGFloat(columns) * cellSize.width
        let contentHeight = CGFloat(rows) * cellSize.height
        let extraH = max(0, imageSize.width - contentWidth)
        let extraV = max(0, imageSize.height - contentHeight)
        return UIEdgeInsets(
            top: floor(extraV / 2),
            left: floor(extraH / 2),
            bottom: ceil(extraV / 2),
            right: ceil(extraH / 2)
        )
    }

    private func extractPixels(
        from cgImage: CGImage,
        row: Int,
        startCol: Int,
        endCol: Int,
        cellSize: CGSize,
        padding: UIEdgeInsets,
        scale: CGFloat
    ) -> [UInt8] {
        let x = Int((padding.left + CGFloat(startCol) * cellSize.width) * scale)
        let y = Int((padding.top + CGFloat(row) * cellSize.height) * scale)
        let w = Int((CGFloat(endCol - startCol) * cellSize.width) * scale)
        let h = Int((cellSize.height) * scale)

        guard w > 0, h > 0,
              x + w <= cgImage.width,
              y + h <= cgImage.height else {
            return []
        }

        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            return []
        }

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    private func pixelMatchRate(_ a: [UInt8], _ b: [UInt8], tolerance: UInt8) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }

        let pixelCount = a.count / 4
        var matchCount = 0

        for i in 0..<pixelCount {
            let offset = i * 4
            let dr = abs(Int(a[offset]) - Int(b[offset]))
            let dg = abs(Int(a[offset + 1]) - Int(b[offset + 1]))
            let db = abs(Int(a[offset + 2]) - Int(b[offset + 2]))
            if dr <= Int(tolerance), dg <= Int(tolerance), db <= Int(tolerance) {
                matchCount += 1
            }
        }

        return Double(matchCount) / Double(pixelCount)
    }
}
