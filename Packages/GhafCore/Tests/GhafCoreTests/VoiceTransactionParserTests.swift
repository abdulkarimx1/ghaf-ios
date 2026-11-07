import XCTest
@testable import GhafCore

final class VoiceTransactionParserTests: XCTestCase {
    func testSplitsMultipleEnglishPurchasesAndPreservesMerchantContext() {
        let drafts = GhafVoiceTransactionParser.parse(
            "I went to supermarket and bought groceries for 560 dhs, then I bought meds for 120dhs",
            languageCode: "en",
            baseCurrency: "AED"
        )

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].amount, Decimal(string: "560"))
        XCTAssertEqual(drafts[0].currency, "AED")
        XCTAssertTrue(drafts[0].merchant.localizedCaseInsensitiveContains("supermarket"))
        XCTAssertTrue(drafts[0].merchant.localizedCaseInsensitiveContains("groceries"))
        XCTAssertEqual(drafts[1].amount, Decimal(string: "120"))
        XCTAssertEqual(drafts[1].merchant, "meds")
        XCTAssertEqual(drafts[0].direction, "debit")
    }

    func testParsesArabicNumeralsAndArabicTransactionSegments() {
        let drafts = GhafVoiceTransactionParser.parse(
            "اشتريت بقالة بمبلغ ٥٦٠ درهم ثم أدوية بمبلغ ١٢٠ درهم",
            languageCode: "ar",
            baseCurrency: "AED"
        )

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].amount, Decimal(string: "560"))
        XCTAssertEqual(drafts[0].merchant, "بقالة")
        XCTAssertEqual(drafts[1].amount, Decimal(string: "120"))
        XCTAssertEqual(drafts[1].merchant, "أدوية")
        XCTAssertEqual(drafts[0].currency, "AED")
    }

    func testParsesThousandsAndDecimalCommaAmounts() {
        let thousands = GhafVoiceTransactionParser.parse(
            "I spent 1,200 AED at supermarket",
            languageCode: "en",
            baseCurrency: "AED"
        )
        let decimalComma = GhafVoiceTransactionParser.parse(
            "I spent 560,50 AED at supermarket",
            languageCode: "en",
            baseCurrency: "AED"
        )

        XCTAssertEqual(thousands.first?.amount, Decimal(string: "1200"))
        XCTAssertEqual(decimalComma.first?.amount, Decimal(string: "560.50"))
    }

    func testRecognizesIncomeLanguage() {
        let english = GhafVoiceTransactionParser.parse(
            "I received salary 5000 AED",
            languageCode: "en",
            baseCurrency: "AED"
        )
        let arabic = GhafVoiceTransactionParser.parse(
            "استلمت راتب ٥٠٠٠ درهم",
            languageCode: "ar",
            baseCurrency: "AED"
        )

        XCTAssertEqual(english.first?.direction, "credit")
        XCTAssertEqual(arabic.first?.direction, "credit")
    }

    func testRecognizesArabicAfternoonTime() {
        let drafts = GhafVoiceTransactionParser.parse(
            "اشتريت أدوية بمبلغ ١٢٠ درهم الساعة ٣ مساءً",
            languageCode: "ar",
            baseCurrency: "AED"
        )

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].merchant, "أدوية")
        XCTAssertEqual(Calendar.current.component(.hour, from: drafts[0].date), 15)
    }
}
