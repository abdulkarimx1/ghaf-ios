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

    func testDeterministicFollowUpSuggestionsAndLedgerMappings() {
        let english = ChatFollowUp.suggestions(after: "How much did I spend this week?", languageCode: "en")
        XCTAssertEqual(english, ["This month vs last", "Top category", "Due subscriptions"])
        XCTAssertEqual(ChatFollowUp.ledgerQuestion(for: english[0], languageCode: "en"),
                       "Compare my spending this month with last month")

        let arabic = ChatFollowUp.suggestions(after: "كم صرفت هالأسبوع؟", languageCode: "ar")
        XCTAssertEqual(arabic, ["مقارنة هذا الشهر بالماضي", "أعلى فئة إنفاقًا", "الاشتراكات القادمة"])
        XCTAssertEqual(ChatFollowUp.ledgerQuestion(for: arabic[2], languageCode: "ar"), "ما الاشتراكات القادمة؟")
    }
}
