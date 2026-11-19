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

    func testLoggingStreakStopsAtGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2024-01-04T12:00:00Z")
        XCTAssertEqual(GhafLoggingStreak.count([date("2024-01-04T08:00:00Z"), date("2024-01-02T08:00:00Z")], through: now, calendar: calendar), 1)
    }

    func testLoggingStreakContinuesThroughYesterdayWhenTodayHasNoTransaction() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2024-01-04T12:00:00Z")
        XCTAssertEqual(GhafLoggingStreak.count([date("2024-01-03T08:00:00Z"), date("2024-01-02T08:00:00Z")], through: now, calendar: calendar), 2)
    }

    func testLoggingStreakUsesCalendarTimezoneForDayBoundaries() {
        let now = date("2024-01-02T00:30:00Z")
        let logs = [date("2024-01-01T23:30:00Z"), date("2024-01-01T05:00:00Z")]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(GhafLoggingStreak.count(logs, through: now, calendar: utc), 1)
        XCTAssertEqual(GhafLoggingStreak.count(logs, through: now, calendar: losAngeles), 2)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

}
