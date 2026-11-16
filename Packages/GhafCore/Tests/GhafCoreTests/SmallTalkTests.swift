import XCTest
@testable import GhafCore

final class SmallTalkTests: XCTestCase {
    func testDetectsOffTopicInBothLanguages() {
        XCTAssertEqual(GhafSmallTalk.topic(of: "What's the weather today?"), .weather)
        XCTAssertEqual(GhafSmallTalk.topic(of: "كيف الجو اليوم"), .weather)
        XCTAssertEqual(GhafSmallTalk.topic(of: "tell me a joke"), .joke)
        XCTAssertNil(GhafSmallTalk.topic(of: "How much did I spend this week?"))
    }

    func testNeverRepeatsWhileAnotherVariantIsLeft() {
        var seen: Set<String> = []
        for _ in 0..<3 {
            let reply = GhafSmallTalk.reply(to: "weather?", languageCode: "en", avoiding: seen)!
            XCTAssertFalse(seen.contains(reply))
            seen.insert(reply)
        }
    }

    func testNotUnderstoodQuotesTheMessageAndVaries() {
        let first = GhafSmallTalk.notUnderstood("blue elephants", languageCode: "en")
        XCTAssertTrue(first.contains("blue elephants"))
        let second = GhafSmallTalk.notUnderstood("blue elephants", languageCode: "en", avoiding: [first])
        XCTAssertNotEqual(first, second)
    }
}
