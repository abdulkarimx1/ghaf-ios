import XCTest
@testable import GhafCore
import Testing

final class BudgetAllocationTests: XCTestCase {
    func testPetalOuterRadiusIsConstantAndSpentUsesBudgetRatio() {
        let halfBudget = BudgetAllocation.petalRadii(budget: 50, spent: 25, innerRadius: 0.16)
        XCTAssertEqual(halfBudget.outer, 1, accuracy: 0.0001)
        XCTAssertEqual(halfBudget.fill, 0.48, accuracy: 0.0001)

        let fullBudget = BudgetAllocation.petalRadii(budget: 100, spent: 100, innerRadius: 0.16)
        XCTAssertEqual(fullBudget.outer, 1, accuracy: 0.0001)
        XCTAssertEqual(fullBudget.fill, 0.8, accuracy: 0.0001)

        let overBudget = BudgetAllocation.petalRadii(budget: 100, spent: 140, innerRadius: 0.16)
        XCTAssertEqual(overBudget.outer, 1, accuracy: 0.0001)
        XCTAssertEqual(overBudget.fill, 0.8, accuracy: 0.0001)

        let unspent = BudgetAllocation.petalRadii(budget: 100, spent: 0, innerRadius: 0.16)
        XCTAssertEqual(unspent, .init(outer: 1, fill: 0.16))
    }

    func testPetalZeroBudgetHasNoSpentFill() {
        let zeroBudget = BudgetAllocation.petalRadii(budget: 0, spent: 0, innerRadius: 0.16)
        XCTAssertEqual(zeroBudget, .init(outer: 1, fill: 0.16))
    }

    func testRemainingAfterSpendingAndSavingsGoal() {
        let remaining = BudgetAllocation.remainingAfterSpending(income: 10_000, needs: 2_500, wants: 2_457.79)
        XCTAssertEqual(remaining, 5_042.21)
        XCTAssertTrue(BudgetAllocation.savingsGoalReached(remaining: remaining, goal: 600))
        XCTAssertFalse(BudgetAllocation.savingsGoalReached(remaining: 599.99, goal: 600))
        XCTAssertFalse(BudgetAllocation.savingsGoalReached(remaining: 100, goal: 0))
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
