import XCTest
@testable import GhafCore

final class FileImportRulesTests: XCTestCase {
    func testDateOnlySameAmountAndMerchantAreSeparatePurchases() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = FileImportIdentity(date: date, hasTime: false, amount: 12, merchant: "Cafe", account: "Main", reference: nil)
        XCTAssertFalse(FileImportRules.isDuplicate(reference: nil, hasTime: false, date: date, amount: 12, merchant: "Cafe", account: "Main", among: [first]))
    }

    func testRowsWithSameTimeOrReferenceAreDuplicates() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = FileImportIdentity(date: date, hasTime: true, amount: 12, merchant: "Cafe", account: "Main", reference: "R-1")
        XCTAssertTrue(FileImportRules.isDuplicate(reference: nil, hasTime: true, date: date, amount: 12, merchant: "Cafe", account: "Main", among: [first]))
        XCTAssertTrue(FileImportRules.isDuplicate(reference: "R-1", hasTime: false, date: date.addingTimeInterval(3600), amount: 12, merchant: "Cafe", account: "Main", among: [first]))
        XCTAssertFalse(FileImportRules.isDuplicate(reference: nil, hasTime: true, date: date.addingTimeInterval(60), amount: 12, merchant: "Cafe", account: "Main", among: [first]))
    }

    func testWholeTokenTypeClassificationAndMissingTypeColumnReview() {
        XCTAssertEqual(FileImportRules.classification(type: "Credit Card Purchase", hasTypeColumn: true, amount: 20, amountHeader: "Amount").direction, .debit)
        XCTAssertEqual(FileImportRules.classification(type: "income", hasTypeColumn: true, amount: -20, amountHeader: "Amount").direction, .credit)
        let ambiguousPositive = FileImportRules.classification(type: nil, hasTypeColumn: false, amount: 20, amountHeader: "Amount")
        XCTAssertEqual(ambiguousPositive, .init(direction: .debit, needsReview: true))
        XCTAssertEqual(FileImportRules.classification(type: nil, hasTypeColumn: false, amount: 20, amountHeader: "Amount", category: "Income"), .init(direction: .debit, needsReview: true))
        XCTAssertEqual(FileImportRules.classification(type: nil, hasTypeColumn: false, amount: 20, amountHeader: "Income Amount"), .init(direction: .credit, needsReview: false))
        XCTAssertEqual(FileImportRules.classification(type: nil, hasTypeColumn: false, amount: -20, amountHeader: "Amount"), .init(direction: .debit, needsReview: false))
    }
}
