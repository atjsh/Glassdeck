import XCTest
@testable import GlassdeckBuildCore

final class SchemeSelectorTests: XCTestCase {
    func testKnownAliasesResolveToCheckedInSchemes() {
        XCTAssertEqual(SchemeSelector(rawValue: "app").schemeName, "GlassdeckApp")
        XCTAssertEqual(SchemeSelector(rawValue: "unit").schemeName, "GlassdeckAppUnit")
        XCTAssertEqual(SchemeSelector(rawValue: "ui").schemeName, "GlassdeckAppUI")
    }
}
