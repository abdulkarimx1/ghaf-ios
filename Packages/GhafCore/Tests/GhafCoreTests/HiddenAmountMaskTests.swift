import XCTest
@testable import GhafCore

final class HiddenAmountMaskTests: XCTestCase {
    func testMasksOnlyWholeNumberDigitsAndPreservesGrouping() {
        XCTAssertEqual(HiddenAmountMask.string(from: "16,999.50"), "★★,★★★")
        XCTAssertEqual(HiddenAmountMask.string(from: "١٬٢٣٤٫٥٦"), "★٬★★★")
        XCTAssertEqual(HiddenAmountMask.string(from: "0.00"), "★")
        XCTAssertEqual(HiddenAmountMask.string(from: "1,234.56"), "★,★★★")
    }
}
