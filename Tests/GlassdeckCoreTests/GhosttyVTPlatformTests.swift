import Foundation
@testable import GlassdeckCore
import XCTest

#if canImport(CGhosttyVT)
final class GhosttyVTPlatformTests: XCTestCase {
    func testVTCurrentSizeAndResize() throws {
        let engine = try GhosttyVTTerminalEngine(
            options: GhosttyVTTerminalOptions(columns: 8, rows: 4, scrollbackLines: 64)
        )

        XCTAssertEqual(try engine.currentSize(), TerminalSize(columns: 8, rows: 4))

        try engine.resize(columns: 10, rows: 5)
        XCTAssertEqual(try engine.currentSize(), TerminalSize(columns: 10, rows: 5))
    }

    func testVTWriteAndDirtyRows() throws {
        let engine = try GhosttyVTTerminalEngine(
            options: GhosttyVTTerminalOptions(columns: 8, rows: 4, scrollbackLines: 64)
        )

        engine.write(Data("abc".utf8))
        let projection = try engine.snapshotProjection(clearDirty: false)

        XCTAssertEqual(projection.columns, 8)
        XCTAssertEqual(projection.rows, 4)
        XCTAssertFalse(projection.dirtyRows.isEmpty)
        XCTAssertTrue(rowText(projection.rowsProjection[0]).hasPrefix("abc"))

        _ = try engine.snapshotProjection(clearDirty: true)
        let cleanProjection = try engine.snapshotProjection(clearDirty: false)
        XCTAssertTrue(cleanProjection.dirtyRows.isEmpty)
    }

    func testVTWriteUsesDistinctForegroundAndBackgroundColors() throws {
        let engine = try GhosttyVTTerminalEngine(
            options: GhosttyVTTerminalOptions(columns: 8, rows: 4, scrollbackLines: 64)
        )

        engine.write(Data("abc".utf8))
        let projection = try engine.snapshotProjection(clearDirty: false)

        XCTAssertNotEqual(projection.foregroundColor, projection.backgroundColor)
    }

    func testInputEncodingHonorsTerminalModes() throws {
        let engine = try GhosttyVTTerminalEngine()

        let plainKey = try XCTUnwrap(
            engine.encodeKey(
                GhosttyVTKeyEventDescriptor(text: "a")
            )
        )
        XCTAssertEqual(plainKey, Data("a".utf8))

        engine.write(Data("\u{1B}[?1004h\u{1B}[?2004h\u{1B}[?2048h\u{1B}[?1000h\u{1B}[?1006h".utf8))

        XCTAssertFalse(try XCTUnwrap(engine.encodeFocus(true)).isEmpty)
        XCTAssertFalse(try XCTUnwrap(engine.encodePaste(Data("paste".utf8))).isEmpty)
        XCTAssertFalse(
            try XCTUnwrap(
                engine.encodeInBandResizeReport(
                    pixelSize: TerminalPixelSize(width: 1200, height: 800),
                    cellPixelSize: TerminalPixelSize(width: 12, height: 24)
                )
            ).isEmpty
        )

        let mouse = try XCTUnwrap(
            engine.encodeMouse(
                GhosttyVTMouseEventDescriptor(
                    action: .press,
                    button: .left,
                    position: GhosttyVTPoint(x: 24, y: 24),
                    sizeContext: GhosttyVTMouseSizeContext(
                        screenWidth: 1200,
                        screenHeight: 800,
                        cellWidth: 12,
                        cellHeight: 24
                    )
                )
            )
        )
        XCTAssertFalse(mouse.isEmpty)
    }

    private func rowText(_ row: GhosttyVTRowProjection) -> String {
        row.cells.map(\.text).joined()
    }
}
#else
final class GhosttyVTFallbackTests: XCTestCase {
    func testEngineUnavailableWithoutCGhosttyVT() {
        XCTAssertThrowsError(try GhosttyVTTerminalEngine())
    }
}
#endif
