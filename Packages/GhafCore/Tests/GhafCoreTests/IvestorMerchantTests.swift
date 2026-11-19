import XCTest
@testable import GhafCore

final class IvestorMerchantTests: XCTestCase {
    private let parser = BankMessageParser()

    func testMerchantStopsBeforeCardClause() throws {
        let text = "You made a purchase of AED 1.00 at Digital Dubai using DFM iVESTOR card xxxx9838. Available Balance AED 11.08."
        let parsed = try XCTUnwrap(parser.parse(text, sender: "iVESTOR", referenceDate: Date()))
        XCTAssertEqual(parsed.merchant, "Digital Dubai")
        XCTAssertEqual(parsed.amount, Decimal(string: "1.00"))
    }

    func testMerchantWithWordWithIsKept() throws {
        let text = "You made a purchase of AED 12.00 at Coffee with Love using your card xxxx1111."
        let parsed = try XCTUnwrap(parser.parse(text, sender: "iVESTOR", referenceDate: Date()))
        XCTAssertEqual(parsed.merchant, "Coffee with Love")
    }
}
