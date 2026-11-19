import XCTest
@testable import GhafCore

final class MemoryIntentTests: XCTestCase {
    func testEnglishCommands() {
        XCTAssertEqual(MemoryIntent.parse("Remember that I prefer short answers"), .remember("I prefer short answers"))
        XCTAssertEqual(MemoryIntent.parse("forget my old budget"), .forget("my old budget"))
        XCTAssertEqual(MemoryIntent.parse("Call me Alex"), .name("Alex"))
        XCTAssertEqual(MemoryIntent.parse("my name is Sam"), .name("Sam"))
        XCTAssertNil(MemoryIntent.parse("do you remember my salary?"))
        XCTAssertNil(MemoryIntent.parse("remember how much I spent last week?"))
        XCTAssertNil(MemoryIntent.parse("remember how much I spent last week"))
    }

    func testArabicCommands() {
        XCTAssertEqual(MemoryIntent.parse("تذكر إن أحب القهوة"), .remember("احب القهوة"))
        XCTAssertEqual(MemoryIntent.parse("تذكّر أفضّل الشاي"), .remember("افضّل الشاي"))
        XCTAssertEqual(MemoryIntent.parse("انسَ ميزانيتي القديمة"), .forget("ميزانيتي القديمة"))
        XCTAssertEqual(MemoryIntent.parse("ناديني خالد"), .name("خالد"))
        XCTAssertEqual(MemoryIntent.parse("اسمي سارة"), .name("سارة"))
        XCTAssertNil(MemoryIntent.parse("هل تتذكر راتبي؟"))
        XCTAssertNil(MemoryIntent.parse("تذكر كم صرفت؟"))
        XCTAssertNil(MemoryIntent.parse("تذكر كم صرفت"))
    }

    func testEmptyAndOverlongCommandsAreIgnored() {
        XCTAssertNil(MemoryIntent.parse("remember"))
        XCTAssertNil(MemoryIntent.parse("remember \(String(repeating: "x", count: 201))"))
    }

    func testMemoryMatchingIsBounded() {
        XCTAssertTrue(MemoryIntent.matches(memory: "I prefer short answers", target: "I prefer short answers"))
        XCTAssertTrue(MemoryIntent.matches(memory: "I prefer short answers", target: "short answers"))
        XCTAssertFalse(MemoryIntent.matches(memory: "I prefer it daily", target: "it"))
        XCTAssertTrue(MemoryIntent.matches(memory: "أحب القهوة العربية", target: "القهوة"))
        XCTAssertTrue(MemoryIntent.matches(memory: "أحب القهوة العربية", target: "القهوة العربية"))
    }
}
