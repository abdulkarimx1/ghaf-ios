import XCTest
@testable import GhafCore

final class ChatFollowUpTests: XCTestCase {
    func testNewPeriodReplacesOld() {
        XCTAssertEqual(ChatFollowUp.resolve("and last month?", previous: "How much did I spend this week?"),
                       "how much did i spend last month")
    }

    func testTopicIsAdded() {
        XCTAssertEqual(ChatFollowUp.resolve("what about food?", previous: "How much did I spend this month?"),
                       "how much did i spend this month food")
    }

    func testArabicFollowUp() {
        XCTAssertEqual(ChatFollowUp.resolve("وأمس؟", previous: "كم صرفت اليوم؟"), "كم صرفت أمس")
    }

    func testStandaloneQuestionsAreUnchanged() {
        XCTAssertEqual(ChatFollowUp.resolve("What's my balance?", previous: "How much did I spend?"), "What's my balance?")
        XCTAssertEqual(ChatFollowUp.resolve("وين أكثر مكان صرفت فيه؟", previous: "كم صرفت اليوم؟"), "وين أكثر مكان صرفت فيه؟")
        XCTAssertEqual(ChatFollowUp.resolve("hello", previous: "How much did I spend?"), "hello")
        XCTAssertEqual(ChatFollowUp.resolve("and last month?", previous: nil), "and last month?")
    }
}
