import XCTest
@testable import GhafCore

/// Bank messages that are not transactions must never become one, even when they name an amount,
/// a currency or the word «خصم» (which also means "discount").
final class PromotionalMessageTests: XCTestCase {
    private let parser = BankMessageParser(defaultCurrency: "AED")

    func testAdvertisementsAreIgnored() {
        let ads = [
            "Mashreq: Enjoy AED 50 off your next purchase at Noon. T&Cs apply.",
            "Mashreq: Get up to 10% cashback on dining this weekend. Apply now: mashreq.com",
            "Spend AED 2,000 with your Mashreq card and win AED 500. Offer valid till 30/11.",
            "استمتع بخصم 50 درهم على مشترياتك من نون باستخدام بطاقة المشرق. تطبق الشروط والأحكام.",
            "عرض حصري: خصم 25% عند الدفع ببطاقتك لدى كارفور لفترة محدودة.",
            "المشرق: احصل على استرجاع نقدي يصل إلى 100 درهم عند الشراء.",
            "Mashreq: Your credit card statement is ready. Minimum payment due AED 250 by 05/12.",
            "Mashreq NEO: Upgrade now and earn rewards on every purchase."
        ]
        for message in ads {
            XCTAssertNil(parser.parse(message, sender: "Mashreq"), "Should ignore: \(message)")
        }
    }

    func testAmountWithoutCurrencyOrEvidenceIsIgnored() {
        XCTAssertNil(parser.parse("Thank you for banking with us. Your reward points: 1200.", sender: "Mashreq"))
        XCTAssertNil(parser.parse("Pay for 3 months and get 1 free.", sender: nil))
    }

    func testRealTransactionsStillRecorded() {
        let cases: [(String, Decimal, TransactionDirection)] = [
            ("Purchase of AED 5.50 was made with Card ending XX123 at SHAY AL NASHAMA CAFET. Available Balance: AED 900.00", 5.50, .debit),
            ("تم خصم 35 درهم من بطاقتك المنتهية ب 1234 لدى مطعم.", 35, .debit),
            ("AED 12,000.00 has been credited to your account XXXX1234 (Salary).", 12000, .credit),
            ("Purchase of AED 12.00 with your card at DEAL MART.", 12, .debit)
        ]
        for (message, amount, direction) in cases {
            let parsed = parser.parse(message, sender: "Mashreq")
            XCTAssertNotNil(parsed, "Should record: \(message)")
            XCTAssertEqual(parsed?.amount, amount)
            XCTAssertEqual(parsed?.direction, direction)
        }
    }
}
