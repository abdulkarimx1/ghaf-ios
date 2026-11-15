import XCTest
@testable import GhafCore

/// Synthetic messages only; no real references or card numbers.
final class TransactionKindTests: XCTestCase {
    private let parser = BankMessageParser()
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func parse(_ text: String) -> ParsedTransaction? {
        parser.parse(text, sender: nil, referenceDate: date)
    }

    func testPlainPurchaseIsStandardDebit() {
        let result = parse("Purchase of AED 40.00 at SAMPLE CAFE was made with your card.")
        XCTAssertEqual(result?.kind, .standard)
        XCTAssertEqual(result?.direction, .debit)
    }

    func testRefundIsCreditRefund() {
        let result = parse("Refund of AED 120.00 from SAMPLE STORE has been credited to your card.")
        XCTAssertEqual(result?.kind, .refund)
        XCTAssertEqual(result?.direction, .credit)
        XCTAssertEqual(result?.amount, 120)
    }

    func testReversalOfPurchaseIsCreditEvenThoughItSaysPurchase() {
        let result = parse("Reversal of purchase AED 55.50 at SAMPLE MARKET.")
        XCTAssertEqual(result?.kind, .reversal)
        XCTAssertEqual(result?.direction, .credit)
    }

    func testReversedCreditThatSaysDebitedIsDebit() {
        let result = parse("Salary credit of AED 500 was reversed and debited from your account.")
        XCTAssertEqual(result?.kind, .reversal)
        XCTAssertEqual(result?.direction, .debit)
    }

    func testPendingAuthorizationIsMarkedPending() {
        let result = parse("Pending authorization: AED 300.00 at SAMPLE HOTEL was charged to your card.")
        XCTAssertEqual(result?.kind, .pending)
    }

    func testBalanceAlertCreatesNothing() {
        XCTAssertNil(parse("Your available balance is AED 2,450.00 as of 12/11/2026."))
    }

    func testOTPWithAmountCreatesNothing() {
        XCTAssertNil(parse("Your OTP for the purchase of AED 99.00 at SAMPLE SHOP is 123456. Do not share it."))
    }
}
