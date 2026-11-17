import XCTest
@testable import GhafCore

final class ForeignCurrencyTests: XCTestCase {
    private let parser = BankMessageParser()

    func testForeignPurchaseIsNotTheAvailableBalance() throws {
        let parsed = try XCTUnwrap(parser.parse(
            "Purchase of TRY 597.60 was made with Card ending XX250 at 4-6 Riverwalk, City West. Available Balance: AED 455.46"))
        XCTAssertEqual(parsed.amount, Decimal(string: "597.60"))
        XCTAssertEqual(parsed.currency, "TRY")
        XCTAssertEqual(parsed.merchant, "4-6 Riverwalk, City West")
    }

    func testBalanceBeforeAmountIsSkipped() throws {
        let parsed = try XCTUnwrap(parser.parse("Avl Bal AED 1,200.00. Your card ending 1234 was debited for AED 45.50 at Carrefour."))
        XCTAssertEqual(parsed.amount, Decimal(string: "45.50"))
        XCTAssertEqual(parsed.currency, "AED")
    }

    func testLowercaseWordIsNotACurrency() {
        XCTAssertNil(parser.parse("Please try 3 times later"))
    }

    func testAmountAfterCode() throws {
        let parsed = try XCTUnwrap(parser.parse("Your card ending 9921 was charged 120.00 GBP at Harrods London."))
        XCTAssertEqual(parsed.currency, "GBP")
        XCTAssertEqual(parsed.amount, 120)
    }

    func testConversionViaBaseRates() throws {
        let rates = ExchangeRates(base: "USD", rates: ["USD": 1, "AED": Decimal(string: "3.6725")!, "TRY": Decimal(string: "34.20")!],
                                  updated: Date(timeIntervalSince1970: 0))
        // 597.60 TRY / 34.20 * 3.6725 = 64.17 AED
        XCTAssertEqual(rates.convert(Decimal(string: "597.60")!, from: "TRY", to: "AED"), Decimal(string: "64.17"))
        XCTAssertEqual(rates.convert(10, from: "AED", to: "AED"), 10)
        XCTAssertNil(rates.convert(10, from: "XYZ", to: "AED"))
    }
}
