import XCTest
@testable import GhafCore

final class BankMessageParserTests: XCTestCase {
    private let parser = BankMessageParser()
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testIgnoresMashreqTransferRequestBecauseItIsNotConfirmed() {
        // SYNTHETIC PLACEHOLDER matching the format; no real reference or
        // phone number is included in the repository.
        let sample = "Mashreq: Request received for fund transfer of AED 1000 (excluding applicable charges) with reference number TESTREF0000000000. Contact your bank if you did not initiate this."

        XCTAssertNil(
            parser.parse(
                sample,
                sender: "Mashreq",
                referenceDate: referenceDate
            )
        )
    }

    func testParsesMbankPurchaseAndKeepsCommaInMerchant() {
        // SYNTHETIC PLACEHOLDER based on the supplied message structure.
        let sample = "Purchase of AED 2.00 was made with Card ending XX000 at SAMPLE MERCHANT, TEST AREA. Available Balance: AED 1.35"

        let result = parser.parse(
            sample,
            sender: "mbank",
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }

        XCTAssertEqual(transaction.amount, Decimal(string: "2.00"))
        XCTAssertEqual(transaction.currency, "AED")
        XCTAssertEqual(transaction.merchant, "SAMPLE MERCHANT, TEST AREA")
        XCTAssertEqual(transaction.direction, .debit)
        XCTAssertEqual(transaction.bank, "mbank")
        XCTAssertTrue(transaction.confidence >= 0.80)

        // No transaction date was present, so referenceDate is used.
        XCTAssertEqual(transaction.date, referenceDate)
    }

    func testParsesIvestorCreditAndDoesNotUseAvailableBalance() {
        // SYNTHETIC PLACEHOLDER based on the supplied message structure.
        let sample = "Your DFM iVESTOR card xxxx0000 has been credited with USD 1.00. Available Balance AED 0.00 (Reversal)"

        let result = parser.parse(
            sample,
            sender: "Ivestor Card",
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }

        XCTAssertEqual(transaction.amount, Decimal(string: "1.00"))
        XCTAssertEqual(transaction.currency, "USD")
        XCTAssertNil(transaction.merchant)
        XCTAssertEqual(transaction.direction, .credit)
        XCTAssertEqual(transaction.bank, "iVESTOR")
        XCTAssertTrue(transaction.confidence >= 0.80)
        XCTAssertEqual(transaction.date, referenceDate)
    }

    func testParsesRuyaDebitAndIgnoresAvailableBalance() {
        // SYNTHETIC PLACEHOLDER based on the supplied message structure.
        let sample = "AED 0.01 has been Debited from your account XXXX000000 on 01-06-2026. Available balance is 0.00"

        let result = parser.parse(
            sample,
            sender: "ruya card",
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }

        XCTAssertEqual(transaction.amount, Decimal(string: "0.01"))
        XCTAssertEqual(transaction.currency, "AED")
        XCTAssertNil(transaction.merchant)
        XCTAssertEqual(transaction.direction, .debit)
        XCTAssertEqual(transaction.bank, "ruya")
        XCTAssertTrue(transaction.confidence >= 0.80)

        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: transaction.date
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 1)
    }

    func testGenericFallbackParsesUnknownBankTransaction() {
        let sample = "Card purchase AED 80.00 at ENOC on 12/05/2026."

        let result = parser.parse(
            sample,
            sender: "Unknown Bank",
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }

        XCTAssertEqual(transaction.amount, Decimal(string: "80.00"))
        XCTAssertEqual(transaction.currency, "AED")
        XCTAssertEqual(transaction.merchant, "ENOC")
        XCTAssertEqual(transaction.direction, .debit)
        XCTAssertNil(transaction.bank)
        XCTAssertFalse(parser.shouldSendToReview(transaction))
    }

    func testMissingCurrencyUsesConfiguredDefaultAndNeedsReview() {
        let customParser = BankMessageParser(defaultCurrency: "AED")
        let sample = "mbank: Debit transaction amount 55.00 at Carrefour."

        let result = customParser.parse(
            sample,
            sender: "mbank",
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }

        XCTAssertEqual(transaction.amount, Decimal(string: "55.00"))
        XCTAssertEqual(transaction.currency, "AED")
        XCTAssertTrue(customParser.shouldSendToReview(transaction))
    }

    func testIgnoresOTPMessage() {
        XCTAssertNil(parser.parse("Your OTP is 123456. Do not share this code with anyone."))
    }

    func testIgnoresPromotionalMessage() {
        XCTAssertNil(parser.parse("Special offer! Get 20% discount on your next purchase."))
    }

    func testIgnoresSecurityAlert() {
        XCTAssertNil(parser.parse("Security alert: A suspicious login attempt was detected."))
    }

    func testIgnoresEmptyMessage() {
        XCTAssertNil(parser.parse(""))
        XCTAssertNil(parser.parse("   \n   "))
    }

    func testAmountWithoutDirectionIsNotLogged() {
        // An amount by itself, including an account balance, is not a
        // completed transaction.
        XCTAssertNil(parser.parse("Account balance AED 15.31"))
    }

    func testConfidenceIsWithinValidRange() {
        let sample = "mbank: Debit AED 40.00 at Carrefour on 12/05/2026."
        let result = parser.parse(
            sample,
            sender: "mbank",
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }
        XCTAssertGreaterThanOrEqual(transaction.confidence, 0.0)
        XCTAssertLessThanOrEqual(transaction.confidence, 1.0)
    }
}
