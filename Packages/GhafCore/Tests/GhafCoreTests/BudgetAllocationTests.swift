import XCTest
@testable import GhafCore
import Testing

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

@Suite struct BudgetAllocationPresetTests {
    @Test func presetsAreCompleteAndUseDecimalAmounts() {
        for preset in BudgetAllocation.Preset.allCases {
            #expect(BudgetAllocation.Bucket.allCases.reduce(Decimal.zero) { $0 + preset.share($1) } == 1)
            #expect(preset.amount(for: .needs, income: 1_000) == 1_000 * preset.share(.needs))
        }
        #expect(BudgetAllocation.Preset.balanced.amount(for: .needs, income: 12_000) == 6_000)
        #expect(BudgetAllocation.Preset.highRentCity.amount(for: .needs, income: 12_000) == 7_200)
        #expect(BudgetAllocation.Preset.saver.amount(for: .savings, income: 12_000) == 3_600)
    }
}
