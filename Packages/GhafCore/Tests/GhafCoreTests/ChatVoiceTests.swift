import XCTest
@testable import GhafCore

final class ChatVoiceTests: XCTestCase {
    func testSpokenMoneyEnglish() {
        XCTAssertEqual(SpokenMoney.speakable("Saved AED 4.00 at Karak.", arabic: false), "Saved 4 dirhams at Karak.")
        XCTAssertEqual(SpokenMoney.speakable("4.50 AED", arabic: false), "4 dirhams 50 fils")
        XCTAssertEqual(SpokenMoney.speakable("AED 1", arabic: false), "1 dirham")
        XCTAssertEqual(SpokenMoney.speakable("AED 1,250.00 · Food", arabic: false), "1,250 dirhams , Food")
    }

    func testSpokenMoneyArabic() {
        XCTAssertEqual(SpokenMoney.words("2", arabic: true), "درهمين")
        XCTAssertTrue(SpokenMoney.words("5", arabic: true).hasSuffix("دراهم"))
        XCTAssertTrue(SpokenMoney.words("35", arabic: true).hasSuffix("درهم"))
        XCTAssertEqual(SpokenMoney.words("1.25", arabic: true), "درهم واحد و25 فلس")
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
