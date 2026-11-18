import XCTest
@testable import GhafCore

final class TransactionEffectTests: XCTestCase {
    func testDirectionAndReversalEffects() {
        let amount: Decimal = 42
        for (isDebit, isReversal, spending, income) in [
            (true, false, 42, 0), (false, false, 0, 42),
            (false, true, -42, 0), (true, true, 0, -42)
        ] as [(Bool, Bool, Decimal, Decimal)] {
            XCTAssertEqual(TransactionEffect.spending(amount: amount, isDebit: isDebit, isReversal: isReversal, countsAsSpendingOrIncome: true), spending)
            XCTAssertEqual(TransactionEffect.income(amount: amount, isDebit: isDebit, isReversal: isReversal, countsAsSpendingOrIncome: true), income)
        }
    }

    func testTransfersAndAdjustmentsHaveNoEffect() {
        for isDebit in [true, false] {
            for isReversal in [true, false] {
                XCTAssertEqual(TransactionEffect.spending(amount: 42, isDebit: isDebit, isReversal: isReversal, countsAsSpendingOrIncome: false), 0)
                XCTAssertEqual(TransactionEffect.income(amount: 42, isDebit: isDebit, isReversal: isReversal, countsAsSpendingOrIncome: false), 0)
            }
        }
    }
}
