import XCTest
@testable import GhafCore

final class SpendingInsightsTests: XCTestCase {
    func testForecastWithoutHistoryFollowsCurrentPace() {
        let f = SpendingInsights.forecast(spentSoFar: 1000, day: 10, daysInMonth: 30, pastMonthTotals: [])
        XCTAssertEqual(f.projected, 3000)
        XCTAssertEqual(f.daysLeft, 20)
        XCTAssertNil(f.typicalMonth)
    }

    func testEarlyInMonthLeansOnHistory() {
        // Day 3 with a big first purchase: history (3000/month) pulls the projection down from 30,000.
        let f = SpendingInsights.forecast(spentSoFar: 3000, day: 3, daysInMonth: 30, pastMonthTotals: [3000, 3000, 3000])
        XCTAssertLessThan(f.projected, 10_000)
        XCTAssertGreaterThan(f.projected, 3000)
        XCTAssertEqual(f.typicalMonth, 3000)
    }

    func testLastDayIsWhatWasSpent() {
        XCTAssertEqual(SpendingInsights.forecast(spentSoFar: 2500, day: 30, daysInMonth: 30, pastMonthTotals: [4000]).projected, 2500)
    }

    func testUnusualChargeNeedsHistoryAndAClearJump() {
        XCTAssertNil(SpendingInsights.unusual(amount: 500, previous: [20, 25]))
        XCTAssertNil(SpendingInsights.unusual(amount: 30, previous: [20, 25, 22, 24]))
        let result = SpendingInsights.unusual(amount: 120, previous: [20, 25, 22, 24])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.typical, 23)
    }
}
