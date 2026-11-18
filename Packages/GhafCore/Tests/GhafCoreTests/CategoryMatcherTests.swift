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

    func testSuggestsNewBuiltInCategoryWhenUserHasNone() {
        let zumba = CategoryMatcher.match("zumba class", catalog: catalog, learned: [:])
        XCTAssertEqual(zumba?.category, "Sports & Fitness")
        XCTAssertEqual(zumba?.subcategory, "Fitness classes")
        XCTAssertEqual(zumba?.isNewCategory, true)
        // One typo is tolerated.
        XCTAssertEqual(CategoryMatcher.match("zuba", catalog: catalog, learned: [:])?.subcategory, "Fitness classes")
        XCTAssertEqual(CategoryMatcher.match("سبا", catalog: catalog, learned: [:])?.category, "Health & Wellness")
    }

    func testSuggestsNewSubcategoryInsideUsersCategory() {
        let rental = CategoryMatcher.match("car rental hertz", catalog: catalog, learned: [:])
        XCTAssertEqual(rental?.category, "Car")
        XCTAssertEqual(rental?.subcategory, "Rental")
        XCTAssertEqual(rental?.isNewSubcategory, true)
        XCTAssertEqual(rental?.isNewCategory, false)
    }

    func testGulfDialectWords() {
        XCTAssertEqual(CategoryMatcher.match("ريوق", catalog: catalog, learned: [:])?.category, "Food")
        XCTAssertEqual(CategoryMatcher.match("قراج", catalog: catalog, learned: [:])?.category, "Car")
        XCTAssertEqual(CategoryMatcher.match("ساهر", catalog: catalog, learned: [:])?.subcategory, "Fines")
    }

    func testOneEditAway() {
        XCTAssertTrue(CategoryMatcher.isOneEditAway("zuba", "zumba"))
        XCTAssertFalse(CategoryMatcher.isOneEditAway("zub", "zumba"))
        XCTAssertFalse(CategoryMatcher.isOneEditAway("zumba", "zumba"))
    }

    func testEveryBuiltInCategoryHasSubcategoriesAndArabic() {
        for category in CategoryTaxonomy.all {
            XCTAssertFalse(category.subcategories.isEmpty, category.name)
            XCTAssertFalse(category.arabic.isEmpty, category.name)
        }
        XCTAssertGreaterThanOrEqual(CategoryTaxonomy.all.count, 15)
    }

    func testArabicNameCoversAliases() {
        XCTAssertEqual(CategoryTaxonomy.arabicName(for: "Food"), CategoryTaxonomy.category(named: "Dining")?.arabic)
        XCTAssertNotNil(CategoryTaxonomy.arabicName(for: "Car"))
        XCTAssertNil(CategoryTaxonomy.arabicName(for: "HDD selling"))
    }

    func testTransfersAreNeverSpending() {
        XCTAssertTrue(CategoryTaxonomy.isTransferOrAdjustment(category: "Transfers", subcategory: nil))
        XCTAssertTrue(CategoryTaxonomy.isTransferOrAdjustment(category: "Adjustment", subcategory: nil))
        // Expend files some transfers as Utilities › Transfer.
        XCTAssertTrue(CategoryTaxonomy.isTransferOrAdjustment(category: "Utilities", subcategory: "Transfer"))
        XCTAssertFalse(CategoryTaxonomy.isTransferOrAdjustment(category: "Utilities", subcategory: "Home rent"))
        XCTAssertFalse(CategoryTaxonomy.isTransferOrAdjustment(category: "Transfer Fee", subcategory: nil))
        XCTAssertFalse(CategoryTaxonomy.isTransferOrAdjustment(category: "Dining", subcategory: nil))
    }
}
