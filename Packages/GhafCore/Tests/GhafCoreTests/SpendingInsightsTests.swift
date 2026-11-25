import XCTest
@testable import GhafCore

final class SpendingInsightsTests: XCTestCase {
    func testChartWindowCountsAndCalendarBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let week = ISO8601DateFormatter().date(from: "2024-02-04T00:00:00Z")!
        let month = ISO8601DateFormatter().date(from: "2024-02-01T00:00:00Z")!
        let quarter = ISO8601DateFormatter().date(from: "2024-02-01T00:00:00Z")!
        let year = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: week)!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: month)!
        let quarterEnd = calendar.date(byAdding: .month, value: 3, to: quarter)!
        let yearEnd = calendar.date(byAdding: .year, value: 1, to: year)!
        let windows: [(SpendingInsights.ChartPeriod, Date, Date, Int)] = [
            (.week, week, weekEnd, 7), (.month, month, monthEnd, 4),
            (.quarter, quarter, quarterEnd, 4), (.year, year, yearEnd, 12)
        ]
        for (period, start, end, expected) in windows {
            let buckets = SpendingInsights.chartWindows(period: period, start: start, end: end, calendar: calendar)
            XCTAssertEqual(buckets.count, expected)
            XCTAssertEqual(buckets.first?.start, start)
            XCTAssertEqual(buckets.last?.end, end)
            XCTAssertTrue(zip(buckets, buckets.dropFirst()).allSatisfy { $0.end == $1.start })
        }
    }

    /// Owner rule, regressed twice (1.29, 1.30): Month and 3M are exactly 4 even bars. Do not change without the owner.
    func testOwnerRule_MonthAndQuarterAreFourEvenBars() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        func day(_ s: String) -> Date { calendar.date(from: DateComponents(year: Int(s.prefix(4)), month: Int(s.dropFirst(5).prefix(2)), day: Int(s.suffix(2))))! }
        let cases: [(SpendingInsights.ChartPeriod, String, Int, Int)] = [
            (.month, "2026-02-01", 1, 28), (.month, "2026-04-01", 1, 30), (.month, "2026-11-01", 1, 30),
            (.month, "2026-12-01", 1, 31), (.quarter, "2026-09-01", 3, 91), (.quarter, "2026-01-01", 3, 90)
        ]
        for (period, from, months, totalDays) in cases {
            let start = day(from), end = calendar.date(byAdding: .month, value: months, to: start)!
            let bars = SpendingInsights.chartWindows(period: period, start: start, end: end, calendar: calendar)
            XCTAssertEqual(bars.count, 4, "\(period) from \(from)")
            let lengths = bars.map { calendar.dateComponents([.day], from: $0.start, to: $0.end).day! }
            XCTAssertEqual(lengths.reduce(0, +), totalDays)
            XCTAssertLessThanOrEqual(lengths.max()! - lengths.min()!, 1, "\(period) from \(from): \(lengths)")
        }
    }

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
