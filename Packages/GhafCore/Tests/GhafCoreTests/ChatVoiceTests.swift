import XCTest
@testable import GhafCore

final class ChatVoiceTests: XCTestCase {
    func testSpokenMoneyEnglish() {
        XCTAssertEqual(SpokenMoney.speakable("Saved AED 4.00 at Karak.", arabic: false), "Saved 4 dirhams at Karak.")
        XCTAssertEqual(SpokenMoney.speakable("4.50 AED", arabic: false), "about 5 dirhams")
        XCTAssertEqual(SpokenMoney.speakable("AED 1", arabic: false), "1 dirham")
        XCTAssertEqual(SpokenMoney.speakable("AED 1,250.00 · Food", arabic: false), "about 1,250 dirhams , Food")
    }

    func testSpokenMoneyArabic() {
        XCTAssertEqual(SpokenMoney.words("2", arabic: true), "درهمين")
        XCTAssertTrue(SpokenMoney.words("5", arabic: true).hasSuffix("دراهم"))
        XCTAssertTrue(SpokenMoney.words("35", arabic: true).hasSuffix("درهم"))
        XCTAssertEqual(SpokenMoney.words("1.25", arabic: true), "حوالي درهم واحد")
        XCTAssertEqual(SpokenMoney.words("1429.29", arabic: true), "حوالي 1,429 درهم")
    }

    func testSpokenMoneyRoundsNaturallyWithoutFils() {
        XCTAssertEqual(SpokenMoney.words("4.50", arabic: false), "about 5 dirhams")
        XCTAssertEqual(SpokenMoney.words("0.40", arabic: false), "less than one dirham")
        XCTAssertEqual(SpokenMoney.words("1.50", arabic: false), "about 2 dirhams")
        XCTAssertEqual(SpokenMoney.words("5", arabic: false), "5 dirhams")
        XCTAssertEqual(SpokenMoney.words("1429.30", arabic: false), "about 1,429 dirhams")
        XCTAssertEqual(SpokenMoney.words("4.50", arabic: true), "حوالي 5 دراهم")
        XCTAssertEqual(SpokenMoney.words("0.40", arabic: true), "أقل من درهم")
        XCTAssertEqual(SpokenMoney.words("1.50", arabic: true), "حوالي درهمين")
        XCTAssertEqual(SpokenMoney.words("5", arabic: true), "5 دراهم")
        XCTAssertEqual(SpokenMoney.words("1429.30", arabic: true), "حوالي 1,429 درهم")
    }

    func testSpeakableDateExpandsAbbreviatedMonth() {
        XCTAssertEqual(SpokenMoney.speakable("Dec 19", arabic: false), "December 19")
        XCTAssertEqual(SpokenMoney.speakable("Dec. 3", arabic: false), "December 3")
    }

    func testConfirmAndCancel() {
        XCTAssertEqual(ChatEdit.parse("Yes", recent: ["Karak"]), .confirm)
        XCTAssertEqual(ChatEdit.parse("احفظها", recent: []), .confirm)
        XCTAssertEqual(ChatEdit.parse("cancel", recent: ["Karak"]), .cancel)
        // "no, it was 5" is a correction, not a cancel.
        XCTAssertNil(ChatEdit.parse("no it was 5", recent: ["Karak"]))
    }

    func testRemoveAndRename() {
        let recent = ["Karak", "Lunch", "Fuel"]
        XCTAssertEqual(ChatEdit.parse("remove the lunch", recent: recent), .remove(1))
        XCTAssertEqual(ChatEdit.parse("delete the last one", recent: recent), .remove(0))
        XCTAssertEqual(ChatEdit.parse("rename karak to tea", recent: recent), .rename(0, "tea"))
        XCTAssertEqual(ChatEdit.parse("شيل البنزين", recent: ["بنزين"]), .remove(0))
        XCTAssertNil(ChatEdit.parse("remove something else", recent: recent))
    }
}
