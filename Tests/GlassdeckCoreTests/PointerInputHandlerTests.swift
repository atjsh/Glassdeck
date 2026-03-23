import XCTest

/// Tests for pointer/mouse input handling patterns.
final class PointerInputHandlerTests: XCTestCase {
    func testScrollDeltaCalculation() {
        let cellHeight: CGFloat = 16.0
        let translation: CGFloat = 48.0
        let rowDelta = Int(translation / cellHeight)
        XCTAssertEqual(rowDelta, 3)
    }

    func testZeroTranslationProducesNoDelta() {
        let cellHeight: CGFloat = 16.0
        let translation: CGFloat = 0.0
        let rowDelta = Int(translation / cellHeight)
        XCTAssertEqual(rowDelta, 0)
    }
}
