import XCTest
@testable import GhafCore

final class AccountTransferMatcherTests: XCTestCase {
    func testNearestEligiblePairIsStableAndDoesNotReuseCredit() {
        let a = UUID(), b = UUID(), c = UUID()
        let d1 = AccountTransferMatcher.Candidate(id: a, accountID: UUID(), amount: 50, currency: "AED", date: .now.addingTimeInterval(-3600), direction: "debit", isReversal: false, hasTransferEvidence: true)
        let d2 = AccountTransferMatcher.Candidate(id: b, accountID: UUID(), amount: 50, currency: "aed", date: .now.addingTimeInterval(-7200), direction: "debit", isReversal: false, hasTransferEvidence: true)
        let credit = AccountTransferMatcher.Candidate(id: c, accountID: UUID(), amount: 50, currency: "AED", date: .now, direction: "credit", isReversal: false, hasTransferEvidence: true)
        let first = AccountTransferMatcher.pairs(in: [d2, credit, d1])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].debitID, a)
        XCTAssertEqual(AccountTransferMatcher.pairs(in: [d2, credit, d1], alreadyPaired: [first[0].key]), [])
    }

    func testRejectsReversalWrongAccountCurrencyAmountOrWindow() {
        let account = UUID()
        let debit = AccountTransferMatcher.Candidate(id: UUID(), accountID: account, amount: 10, currency: "AED", date: .now, direction: "debit", isReversal: false, hasTransferEvidence: true)
        let noMatch = AccountTransferMatcher.Candidate(id: UUID(), accountID: account, amount: 10, currency: "AED", date: .now, direction: "credit", isReversal: false, hasTransferEvidence: true)
        XCTAssertTrue(AccountTransferMatcher.pairs(in: [debit, noMatch]).isEmpty)
        let far = AccountTransferMatcher.Candidate(id: UUID(), accountID: UUID(), amount: 10, currency: "AED", date: .now.addingTimeInterval(4 * 86_400), direction: "credit", isReversal: false, hasTransferEvidence: true)
        XCTAssertTrue(AccountTransferMatcher.pairs(in: [debit, far]).isEmpty)
    }
}
