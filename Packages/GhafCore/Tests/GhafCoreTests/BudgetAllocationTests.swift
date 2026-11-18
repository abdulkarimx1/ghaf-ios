import XCTest
@testable import GhafCore

final class BudgetAllocationTests: XCTestCase {
    func testEssentialsAreNeeds() {
        for name in ["Groceries", "Housing", "Bills & Utilities", "Utilities", "Car", "Fuel", "Home rent", "Rent"] {
            XCTAssertEqual(BudgetAllocation.bucket(forCategory: name), .needs, name)
        }
    }

    func testEverythingElseIsAWant() {
        for name in ["Entertainment", "Shopping", "Food & Dining", "Dinner", "Travel", "My custom thing"] {
            XCTAssertEqual(BudgetAllocation.bucket(forCategory: name), .wants, name)
        }
    }

    func testSharesAddUpToIncome() {
        XCTAssertEqual(BudgetAllocation.Bucket.allCases.reduce(Decimal.zero) { $0 + BudgetAllocation.share($1) }, 1)
    }
}
