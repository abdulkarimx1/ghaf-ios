import Foundation
import Testing
@testable import GhafCore

@Suite struct SpendingForecastTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))! }

    private func date(_ dayOffset: Int) -> Date { calendar.date(byAdding: .day, value: dayOffset, to: now)! }

    @Test func requiresFourteenDaysOfHistory() {
        let history = (-13...0).map { SpendingForecast.Expense(date: date($0), amount: 100) }
        let forecast = SpendingForecast.amounts(expenses: history, windows: [.init(start: now, end: date(3))], now: now, calendar: calendar)
        #expect(forecast.isEmpty)
    }

    @Test func comparisonRequiresEightyPercentOfPreviousPeriodInLedger() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let first = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        #expect(!SpendingForecast.hasPreviousPeriodCoverage(firstTransactionDate: nil, start: start, end: end, calendar: calendar))
        #expect(!SpendingForecast.hasPreviousPeriodCoverage(firstTransactionDate: first, start: start, end: end, calendar: calendar))
        #expect(SpendingForecast.hasPreviousPeriodCoverage(firstTransactionDate: start, start: start, end: end, calendar: calendar))
    }

    @Test func averagesHistoryCapsOutlierExcludesTransfersAndAddsDueSubscriptions() {
        var history = (-14...0).map { SpendingForecast.Expense(date: date($0), amount: 100) }
        history.append(.init(date: date(-10), amount: 10_000))
        history.append(.init(date: date(-8), amount: 900, isTransfer: true))
        let due = [
            SpendingForecast.Subscription(nextPaymentDate: date(1), amount: 35),
            SpendingForecast.Subscription(nextPaymentDate: date(2), amount: 50, isActive: false),
            SpendingForecast.Subscription(nextPaymentDate: date(5), amount: 75)
        ]
        let windows = [SpendingForecast.Window(start: now, end: date(3)), .init(start: date(3), end: date(6))]

        let forecast = SpendingForecast.amounts(expenses: history, subscriptions: due, windows: windows, now: now, calendar: calendar)

        #expect(forecast[windows[0].start] == 235)
        #expect(forecast[windows[1].start] == 375)
    }
}
