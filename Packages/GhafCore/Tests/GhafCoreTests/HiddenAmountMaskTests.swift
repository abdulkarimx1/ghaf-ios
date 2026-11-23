import XCTest
@testable import GhafCore

final class HiddenAmountMaskTests: XCTestCase {
    func testMasksEveryDigitAndPreservesSeparators() {
        XCTAssertEqual(HiddenAmountMask.string(from: "16,999.50"), "••,•••.••")
        XCTAssertEqual(HiddenAmountMask.string(from: "١٬٢٣٤٫٥٦"), "•٬•••٫••")
        XCTAssertEqual(HiddenAmountMask.string(from: "0.50"), "•.••")
        XCTAssertEqual(HiddenAmountMask.string(from: "1"), "•")
        XCTAssertEqual(HiddenAmountMask.string(from: "1,000,000.00"), "•,•••,•••.••")
    }
}
