import Foundation

/// A deterministic estimate of spending after `now`, using up to 90 days of ledger history.
public enum SpendingForecast {
    /// A comparison is useful only when at least 80% of the previous period is covered by ledger history.
    public static func hasPreviousPeriodCoverage(firstTransactionDate: Date?, start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        guard let firstTransactionDate, start < end else { return false }
        let periodDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        guard periodDays > 0 else { return false }
        let coveredStart = max(start, calendar.startOfDay(for: firstTransactionDate))
        let coveredDays = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: coveredStart), to: calendar.startOfDay(for: end)).day ?? 0)
        return Double(coveredDays) / Double(periodDays) >= 0.8
    }

    public struct Expense: Sendable {
        public let date: Date
        public let amount: Decimal
        public let isExpense: Bool
        public let isTransfer: Bool

        public init(date: Date, amount: Decimal, isExpense: Bool = true, isTransfer: Bool = false) {
            self.date = date
            self.amount = amount
            self.isExpense = isExpense
            self.isTransfer = isTransfer
        }
    }

    public struct Subscription: Sendable {
        public let nextPaymentDate: Date
        public let amount: Decimal
        public let isActive: Bool

        public init(nextPaymentDate: Date, amount: Decimal, isActive: Bool = true) {
            self.nextPaymentDate = nextPaymentDate
            self.amount = amount
            self.isActive = isActive
        }
    }

    public struct Window: Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// Returns forecast amounts keyed by each window's start. Windows use half-open date ranges.
    public static func amounts(
        expenses: [Expense], subscriptions: [Subscription] = [], windows: [Window],
        now: Date = .now, calendar: Calendar = .current
    ) -> [Date: Decimal] {
        let eligible = expenses.filter { $0.isExpense && !$0.isTransfer && $0.amount > 0 && $0.date <= now }
        guard let first = eligible.map(\.date).min() else { return [:] }
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.startOfDay(for: max(first, calendar.date(byAdding: .day, value: -89, to: today)!))
        let historyDays = calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0
        guard historyDays >= 14 else { return [:] }

        var daily: [Date: Decimal] = [:]
        for expense in eligible where expense.date >= firstDay {
            let day = calendar.startOfDay(for: expense.date)
            daily[day, default: 0] += expense.amount
        }
        let observedDays = historyDays + 1
        let values = (0..<observedDays).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }.map { daily[$0, default: 0] }.sorted()
        let capIndex = min(values.count - 1, max(0, Int(Double(values.count - 1) * 0.95)))
        let cap = values[capIndex]
        let cappedTotal = values.reduce(Decimal.zero) { $0 + min($1, cap) }
        let average = cappedTotal / Decimal(observedDays)

        return Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            let start = max(now, window.start)
            guard start < window.end else { return nil }
            let dayCount = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: window.end)).day ?? 0)
            var dailyEstimate = average * Decimal(dayCount)
            if calendar.isDate(start, inSameDayAs: now), dayCount > 0 {
                dailyEstimate -= min(average, daily[today, default: 0])
            }
            let due = subscriptions.filter { $0.isActive && $0.amount > 0 && $0.nextPaymentDate >= start && $0.nextPaymentDate < window.end }
                .reduce(Decimal.zero) { $0 + $1.amount }
            return (window.start, dailyEstimate + due)
        })
    }
}
