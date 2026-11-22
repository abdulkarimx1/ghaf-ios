import XCTest
@testable import GhafCore
import Testing

final class BudgetAllocationTests: XCTestCase {
    func testPetalBudgetAndSpentRadiiAreProportionalAndCapped() {
        let halfBudget = BudgetAllocation.petalRadii(budget: 50, spent: 25, largestBudget: 100, innerRadius: 0.5)
        XCTAssertEqual(halfBudget.outer, 0.75, accuracy: 0.0001)
        XCTAssertEqual(halfBudget.fill, 0.625, accuracy: 0.0001)

        let overBudget = BudgetAllocation.petalRadii(budget: 100, spent: 140, largestBudget: 100, innerRadius: 0.5)
        XCTAssertEqual(overBudget.outer, 1, accuracy: 0.0001)
        XCTAssertEqual(overBudget.fill, 1, accuracy: 0.0001)

        let empty = BudgetAllocation.petalRadii(budget: 0, spent: 0, largestBudget: 100, innerRadius: 0.5)
        XCTAssertEqual(empty, .init(outer: 0.5, fill: 0.5))
    }

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
        #expect(BudgetAllocation.Preset.essentialsFirst.amount(for: .savings, income: 12_000) == 1_200)
        #expect(BudgetAllocation.Preset.guardian.rawValue == "guardian")
        #expect(BudgetAllocation.Preset.guardian.amount(for: .needs, income: 12_000) == 8_400)
    }
}
