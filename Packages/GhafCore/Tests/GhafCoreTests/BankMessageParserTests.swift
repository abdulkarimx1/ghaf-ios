import XCTest
@testable import GhafCore

final class BankMessageParserTests: XCTestCase {
    private let parser = BankMessageParser()
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesSpelledDateAndCleansTruncatedMerchant() throws {
        let sample = "Purchase of AED 18.00 with your card at KOOKH AL SHAY CAFETER on Thursday, 19 November 2026, 6:11 am"
        let transaction = try XCTUnwrap(parser.parse(sample, sender: nil, referenceDate: referenceDate))
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(MerchantName.expand(MerchantName.clean(transaction.merchant ?? ""), known: []), "KOOKH AL SHAY CAFETERIA")
        XCTAssertEqual(calendar.dateComponents(in: TimeZone.current, from: transaction.date).year, 2026)
        XCTAssertEqual(calendar.dateComponents(in: TimeZone.current, from: transaction.date).month, 11)
        XCTAssertEqual(calendar.dateComponents(in: TimeZone.current, from: transaction.date).day, 19)
        XCTAssertEqual(calendar.dateComponents(in: TimeZone.current, from: transaction.date).hour, 6)
        XCTAssertEqual(calendar.dateComponents(in: TimeZone.current, from: transaction.date).minute, 11)
    }

    func testParsesAlternativeSpelledDateForms() throws {
        for phrase in ["19 November 2026 06:11", "19 Nov 2026 6:11 PM", "Nov 19, 2026 6:11am"] {
            let transaction = try XCTUnwrap(parser.parse("Purchase of AED 18.00 at SAMPLE SHOP on \(phrase)", sender: nil, referenceDate: referenceDate))
            XCTAssertEqual(Calendar.current.component(.year, from: transaction.date), 2026, phrase)
        }
    }

    func testCleansArabicMerchantBeforeDatedTail() throws {
        let transaction = try XCTUnwrap(parser.parse(
            "تم خصم مبلغ 18.00 AED لدى مقهى النور بتاريخ ١٩/١١/٢٠٢٦",
            sender: nil,
            referenceDate: referenceDate
        ))
        XCTAssertEqual(transaction.merchant, "مقهى النور")
        XCTAssertEqual(Calendar.current.component(.year, from: transaction.date), 2026)
    }

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
        XCTAssertEqual(transaction.accountRef, "000")
        XCTAssertTrue(transaction.confidence >= 0.80)

        // No transaction date was present, so referenceDate is used.
        XCTAssertEqual(transaction.date, referenceDate)
    }

    func testParsesBankNotificationBodyWithoutSenderMetadata() {
        // Notification automations pass the notification content as text;
        // the originating app name is not a separate input to Ghaf.
        let sample = "Purchase of AED 2.00 was made with Card ending XX000 at SAMPLE MERCHANT. Available Balance: AED 1.35"

        let result = parser.parse(
            sample,
            sender: nil,
            referenceDate: referenceDate
        )

        XCTAssertNotNil(result)
        guard let transaction = result else { return }
        XCTAssertEqual(transaction.amount, Decimal(string: "2.00"))
        XCTAssertEqual(transaction.currency, "AED")
        XCTAssertEqual(transaction.merchant, "SAMPLE MERCHANT")
        XCTAssertEqual(transaction.direction, .debit)
        XCTAssertNil(transaction.bank)
        XCTAssertFalse(parser.shouldSendToReview(transaction))
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
        XCTAssertEqual(transaction.accountRef, "0000")
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
        XCTAssertEqual(transaction.accountRef, "0000")
        XCTAssertTrue(transaction.confidence >= 0.80)

        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: transaction.date
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 1)
    }

    func testExtractsMashreqCardReferenceAndArabicReference() {
        XCTAssertEqual(parser.parse("Mashreq: AED 8.00 was debited from card ending 1234 at Shop.", referenceDate: referenceDate)?.accountRef, "1234")
        XCTAssertEqual(parser.parse("تم خصم 8 درهم من البطاقة المنتهية بـ ١٢٣٤ لدى متجر.", referenceDate: referenceDate)?.accountRef, "1234")
    }

    func testExtractsAccountReferenceAndLeavesMissingReferenceNil() {
        XCTAssertEqual(parser.parse("ruya: AED 8.00 was debited from a/c XXXX5678.", referenceDate: referenceDate)?.accountRef, "5678")
        XCTAssertNil(parser.parse("Mashreq: AED 8.00 was debited at Shop.", referenceDate: referenceDate)?.accountRef)
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

    func testParsesAllSupportedGCCCurrencyCodes() {
        let currencies = ["AED", "SAR", "KWD", "BHD", "OMR", "QAR"]

        for currency in currencies {
            let sample = "Card purchase \(currency) 12.50 at SAMPLE MERCHANT."
            let result = parser.parse(
                sample,
                sender: "Unknown Bank",
                referenceDate: referenceDate
            )

            XCTAssertNotNil(result, "Expected parser to recognize \(currency)")
            XCTAssertEqual(result?.currency, currency)
            XCTAssertEqual(result?.amount, Decimal(string: "12.50"))
        }
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
