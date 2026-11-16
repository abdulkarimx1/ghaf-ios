import XCTest
@testable import GhafCore

/// Synthetic Arabic messages only.
final class ArabicBankMessageTests: XCTestCase {
    private let parser = BankMessageParser()
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private func parse(_ text: String) -> ParsedTransaction? { parser.parse(text, sender: nil, referenceDate: date) }

    func testArabicDigitsAndDirhamDebitWithMerchant() {
        let result = parse("تم خصم ١٢٥٫٥٠ درهم من بطاقتك لدى مقهى تجريبي.")
        XCTAssertEqual(result?.amount, Decimal(string: "125.50"))
        XCTAssertEqual(result?.currency, "AED")
        XCTAssertEqual(result?.direction, .debit)
        XCTAssertEqual(result?.merchant, "مقهى تجريبي")
    }

    func testArabicDepositWithThousandsSeparator() {
        let result = parse("تم إيداع ١٢٬٠٠٠ درهم راتب في حسابك.")
        XCTAssertEqual(result?.amount, 12_000)
        XCTAssertEqual(result?.direction, .credit)
    }

    func testSaudiRiyalIsSAR() {
        XCTAssertEqual(parse("عملية شراء بمبلغ 40 ريال سعودي لدى متجر.")?.currency, "SAR")
    }

    func testArabicRefundIsCredit() {
        let result = parse("تم استرداد مبلغ 60 درهم لدى متجر تجريبي.")
        XCTAssertEqual(result?.kind, .refund)
        XCTAssertEqual(result?.direction, .credit)
    }

    func testArabicPromoWithDiscountCreatesNothing() {
        XCTAssertNil(parse("احصل على خصم 20% عند الشراء بمبلغ 200 درهم من متجرنا."))
    }

    func testArabicOTPCreatesNothing() {
        XCTAssertNil(parse("رمز التحقق لعملية شراء بمبلغ 99 درهم هو 4821. لا تشارك الرمز."))
    }
}
