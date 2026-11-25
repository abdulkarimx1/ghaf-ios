import XCTest
@testable import GhafCore

final class FileImportTypeTests: XCTestCase {
    /// R9: plural and short bank Type values are spending, and an unknown positive Type is never silent income.
    func testPurchaseLikeTypesAreSpending() {
        for type in ["Purchases", "POS", "Payments", "ATM", "Card Purchase", "مشتريات"] {
            let result = FileImportRules.classification(type: type, hasTypeColumn: true, amount: 42, amountHeader: "Amount")
            XCTAssertEqual(result.direction, .debit, type)
            XCTAssertFalse(result.needsReview, type)
        }
        XCTAssertEqual(FileImportRules.classification(type: "Salary", hasTypeColumn: true, amount: 9000, amountHeader: "Amount").direction, .credit)
        let unknown = FileImportRules.classification(type: "Misc", hasTypeColumn: true, amount: 10, amountHeader: "Amount")
        XCTAssertEqual(unknown.direction, .debit)
        XCTAssertTrue(unknown.needsReview)
    }
}
