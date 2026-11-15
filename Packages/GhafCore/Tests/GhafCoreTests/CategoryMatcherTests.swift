import XCTest
@testable import GhafCore

final class CategoryMatcherTests: XCTestCase {
    // Mirrors the user's real Expend setup.
    let catalog: [String: [String]] = [
        "Food": ["Lunch", "Dinner", "Cafeteria"],
        "Car": ["Fuel", "Parking", "Wash", "Fines"],
        "Subscriptions": ["Claude", "Chat GPT", "iCloud+"],
        "Grocery": [],
        "Utilities": ["Du", "Home rent"]
    ]

    func testLearnedMerchantWins() {
        let learned = ["kfc": CategoryMatcher.Rule(category: "Food", subcategory: "Dinner", hits: 4)]
        let match = CategoryMatcher.match("KFC", catalog: catalog, learned: learned)
        XCTAssertEqual(match?.category, "Food")
        XCTAssertEqual(match?.subcategory, "Dinner")
        XCTAssertEqual(match?.source, .learned)
    }

    func testLearnedMerchantInsideLongerText() {
        let learned = ["adnoc": CategoryMatcher.Rule(category: "Car", subcategory: "Fuel", hits: 9)]
        let match = CategoryMatcher.match("adnoc station 23", catalog: catalog, learned: learned)
        XCTAssertEqual(match?.category, "Car")
        XCTAssertEqual(match?.subcategory, "Fuel")
    }

    func testSubcategoryNameMatches() {
        let match = CategoryMatcher.match("lunch", catalog: catalog, learned: [:])
        XCTAssertEqual(match?.category, "Food")
        XCTAssertEqual(match?.subcategory, "Lunch")
        let claude = CategoryMatcher.match("Claude.ai subscription", catalog: catalog, learned: [:])
        XCTAssertEqual(claude?.subcategory, "Claude")
    }

    func testSynonymMapsToUsersOwnCategoryName() {
        // "petrol" is not a category or subcategory, but belongs to the fuel concept → Car/Fuel.
        let match = CategoryMatcher.match("petrol", catalog: catalog, learned: [:])
        XCTAssertEqual(match?.category, "Car")
        XCTAssertEqual(match?.subcategory, "Fuel")
        let shawarma = CategoryMatcher.match("shawarma", catalog: catalog, learned: [:])
        XCTAssertEqual(shawarma?.category, "Food")
        let arabic = CategoryMatcher.match("بنزين", catalog: catalog, learned: [:])
        XCTAssertEqual(arabic?.category, "Car")
    }

    func testUnknownTextReturnsNil() {
        XCTAssertNil(CategoryMatcher.match("zxq widget", catalog: catalog, learned: [:]))
        XCTAssertNil(CategoryMatcher.match("", catalog: catalog, learned: [:]))
    }

    func testShortWordsDoNotMatchInsideOtherWords() {
        // "du" must not match "dubai mall".
        XCTAssertNotEqual(CategoryMatcher.match("dubai mall", catalog: catalog, learned: [:])?.subcategory, "Du")
    }

    func testLearnerTakesMajorityAndCounts() {
        let history: [CategoryMatcher.Example] = [
            .init(merchant: "Lunch", category: "Food", subcategory: "Lunch"),
            .init(merchant: "lunch", category: "Food", subcategory: "Lunch"),
            .init(merchant: "LUNCH", category: "Food", subcategory: "Dinner"),
            .init(merchant: "", category: "Food", subcategory: nil),
            .init(merchant: "Adjust", category: "Other", subcategory: nil)
        ]
        let rules = CategoryMatcher.learn(from: history)
        XCTAssertEqual(rules["lunch"], CategoryMatcher.Rule(category: "Food", subcategory: "Lunch", hits: 3))
        XCTAssertNil(rules["adjust"], "Other is never learned")
        XCTAssertEqual(rules.count, 1)
    }
}
