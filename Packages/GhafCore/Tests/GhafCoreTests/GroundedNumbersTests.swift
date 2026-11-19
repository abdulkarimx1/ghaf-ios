import XCTest
@testable import GhafCore

final class GroundedNumbersTests: XCTestCase {
    func testExactMatchAndGrouping() {
        XCTAssertEqual(GroundedNumbers.unsupported(in: "Spent 1234.50 and 1,234.50 AED", sources: ["1234.50 AED"]), [])
    }

    func testArabicIndicDigitsAndSeparators() {
        XCTAssertEqual(GroundedNumbers.unsupported(in: "أنفقت ١٢٣٫٥٠", sources: ["123.50"]), [])
    }

    func testRoundedSourceNumberIsSupported() {
        XCTAssertEqual(GroundedNumbers.unsupported(in: "About 1,235", sources: ["1234.50"]), [])
    }

    func testSmallIntegersAndYearsAreIgnored() {
        XCTAssertEqual(GroundedNumbers.unsupported(in: "3 items in 2026", sources: []), [])
    }

    func testInventedFigureIsReported() {
        XCTAssertEqual(GroundedNumbers.unsupported(in: "Your total is 725 AED", sources: ["Spent 35 AED"]), [725])
    }

    func testUnsupportedDuplicatesAreReportedOnce() {
        XCTAssertEqual(GroundedNumbers.unsupported(in: "725 then 725.00", sources: []), [725])
    }
}
