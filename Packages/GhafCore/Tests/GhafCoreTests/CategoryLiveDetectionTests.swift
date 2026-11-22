import XCTest
@testable import GhafCore

final class CategoryLiveDetectionTests: XCTestCase {
    func testReplacingArabicMerchantTextReplacesTheCurrentSuggestion() throws {
        let catalog = Dictionary(uniqueKeysWithValues: CategoryTaxonomy.all.map { ($0.name, $0.subcategories.map(\.name)) })

        let first = try XCTUnwrap(CategoryMatcher.match("ورد", catalog: catalog, learned: [:]))
        XCTAssertEqual(first.category, "Shopping")
        XCTAssertEqual(first.subcategory, "Gifts")

        let replacement = try XCTUnwrap(CategoryMatcher.match("فحص دم", catalog: catalog, learned: [:]))
        XCTAssertEqual(replacement.category, "Health & Wellness")
        XCTAssertEqual(replacement.subcategory, "Lab tests")
    }
}
