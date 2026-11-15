import XCTest
@testable import GhafCore

final class NumberWordsTests: XCTestCase {
    func testEnglish() {
        XCTAssertEqual(NumberWords.replace(in: "twenty five dirhams lunch"), "25 dirhams lunch")
        XCTAssertEqual(NumberWords.replace(in: "one hundred and twenty petrol"), "120 petrol")
        XCTAssertEqual(NumberWords.replace(in: "a thousand for rent"), "1000 for rent")
        XCTAssertEqual(NumberWords.replace(in: "two thousand five hundred salary"), "2500 salary")
    }

    func testGulfArabic() {
        XCTAssertEqual(NumberWords.replace(in: "خمسة وعشرين درهم غداء"), "25 درهم غداء")
        XCTAssertEqual(NumberWords.replace(in: "مية وخمسين بنزين"), "150 بنزين")
        XCTAssertEqual(NumberWords.replace(in: "كرك بخمسة دراهم"), "كرك 5 دراهم")
        XCTAssertEqual(NumberWords.replace(in: "خمستعش درهم"), "15 درهم")
        XCTAssertEqual(NumberWords.replace(in: "الفين ايجار"), "2000 ايجار")
        XCTAssertEqual(NumberWords.replace(in: "خمسة ونص"), "5.5")
    }

    func testLeavesTextWithDigitsAndPlainWordsAlone() {
        XCTAssertEqual(NumberWords.replace(in: "one coffee 15"), "one coffee 15")
        XCTAssertEqual(NumberWords.replace(in: "karak 3 and zumba two hundred fifty"), "karak 3 and zumba 250")
        XCTAssertEqual(NumberWords.replace(in: "coffee and cake"), "coffee and cake")
        XCTAssertEqual(NumberWords.replace(in: "a coffee"), "a coffee")
    }

    func testParserUnderstandsSpokenAmounts() {
        let drafts = GhafVoiceTransactionParser.parse("karak five dirhams and petrol one hundred twenty", languageCode: "en", baseCurrency: "AED")
        XCTAssertEqual(drafts.map(\.amount), [5, 120])
        let arabic = GhafVoiceTransactionParser.parse("شريت كرك بخمسة دراهم", languageCode: "ar", baseCurrency: "AED")
        XCTAssertEqual(arabic.first?.amount, 5)
        XCTAssertEqual(arabic.first?.merchant, "كرك")
    }
}
