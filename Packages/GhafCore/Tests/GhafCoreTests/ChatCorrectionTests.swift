import XCTest
@testable import GhafCore

final class ChatCorrectionTests: XCTestCase {
    func testEditsNamedEntry() {
        XCTAssertEqual(ChatCorrection.parse("no, edit karak it was 5 dhs", recent: ["zumba class", "petrol", "karak"]),
                       .init(index: 2, amount: 5))
    }

    func testArabicWithArticle() {
        XCTAssertEqual(ChatCorrection.parse("لا، الكرك كان ٥ دراهم", recent: ["بنزين", "كرك"]), .init(index: 1, amount: 5))
    }

    func testBareCorrectionTargetsLatest() {
        XCTAssertEqual(ChatCorrection.parse("no it was seven", recent: ["petrol"]), .init(index: 0, amount: 7))
    }

    func testNewPurchasesAreNotCorrections() {
        XCTAssertNil(ChatCorrection.parse("change oil 120", recent: ["karak"]))
        XCTAssertNil(ChatCorrection.parse("karak 5", recent: ["karak"]))
        XCTAssertNil(ChatCorrection.parse("no", recent: []))
    }
}
