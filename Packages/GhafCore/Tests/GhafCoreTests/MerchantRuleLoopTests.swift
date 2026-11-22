import XCTest
@testable import GhafCore

final class MerchantRuleLoopTests: XCTestCase {
    func testConfirmedMerchantCategoryAndSubcategoryApplyToNextVariant() {
        let correction = CategoryMatcher.Example(
            merchant: "Shay Al Nashama",
            category: "Food",
            subcategory: "Cafeteria"
        )
        let learnedRules = CategoryMatcher.learn(from: [correction])
        let nextTransaction = CategoryMatcher.match(
            "SHAY AL NASHAMA Tea",
            catalog: ["Food": ["Cafeteria"]],
            learned: learnedRules
        )

        XCTAssertEqual(learnedRules["shay al nashama"], .init(category: "Food", subcategory: "Cafeteria", hits: 1))
        XCTAssertEqual(nextTransaction?.category, "Food")
        XCTAssertEqual(nextTransaction?.subcategory, "Cafeteria")
        XCTAssertEqual(nextTransaction?.source, .learned)
    }
}
