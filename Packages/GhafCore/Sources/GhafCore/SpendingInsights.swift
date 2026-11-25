import Foundation

/// Statistics that look ahead: a month-end spending forecast and unusual-charge detection.
/// Plain arithmetic on the user's own history, so every figure can be explained.
public enum SpendingInsights {

    public enum ChartPeriod: Sendable { case week, month, quarter, year }

    public struct Window: Equatable, Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) { self.start = start; self.end = end }
    }

    /// Calendar-aligned buckets for the Statistics chart. Owner rule (1.31, locked by
    /// `testOwnerRule_MonthAndQuarterAreFourEvenBars`): week = 7 daily bars, month = 4 even bars,
    /// 3 months = 4 even bars, year = 12 monthly bars. Even = whole days, sizes differ by at most one day.
    public static func chartWindows(period: ChartPeriod, start: Date, end: Date, calendar: Calendar) -> [Window] {
        guard start < end else { return [] }
        var boundaries = [start]
        switch period {
        case .week, .year:
            let unit: Calendar.Component = period == .week ? .day : .month
            for index in 1..<(period == .week ? 7 : 12) {
                if let boundary = calendar.date(byAdding: unit, value: index, to: start),
                   boundary > boundaries.last!, boundary < end { boundaries.append(boundary) }
            }
        case .month, .quarter:
            let days = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
            let bars = min(4, days), base = days / bars, extra = days % bars
            var offset = 0
            for index in 0..<(bars - 1) {
                offset += base + (index < extra ? 1 : 0)
                if let boundary = calendar.date(byAdding: .day, value: offset, to: start),
                   boundary > boundaries.last!, boundary < end { boundaries.append(boundary) }
            }
        }
        return boundaries.enumerated().map { index, boundary in
            Window(start: boundary, end: index + 1 < boundaries.count ? boundaries[index + 1] : end)
        }
    }

    public struct Forecast: Equatable {
        public let projected: Decimal
        public let spentSoFar: Decimal
        public let daysLeft: Int
        /// Average monthly spending over the months used as history, or nil without history.
        public let typicalMonth: Decimal?
    }

    /// Month-end projection. Early in the month the usual daily rate from past months dominates; as the
    /// month goes on, this month's own pace takes over. `pastMonthTotals` are complete earlier months.
    public static func forecast(spentSoFar: Decimal, day: Int, daysInMonth: Int, pastMonthTotals: [Decimal]) -> Forecast {
        let day = max(1, min(day, daysInMonth))
        let daysLeft = daysInMonth - day
        let currentRate = spentSoFar / Decimal(day)
        let history = pastMonthTotals.filter { $0 > 0 }
        let typical = history.isEmpty ? nil : history.reduce(0, +) / Decimal(history.count)
        let rate: Decimal
        if let typical {
            let weight = Decimal(day) / Decimal(daysInMonth)
            rate = weight * currentRate + (1 - weight) * (typical / Decimal(daysInMonth))
        } else {
            rate = currentRate
        }
        return Forecast(projected: spentSoFar + rate * Decimal(daysLeft), spentSoFar: spentSoFar,
                        daysLeft: daysLeft, typicalMonth: typical)
    }

    public struct Unusual: Equatable {
        /// What a charge here usually costs (the median of earlier charges).
        public let typical: Decimal
        public let times: Double
    }

    /// A charge is unusual when there are at least 3 earlier charges at the same place and it is more
    /// than double their median and above their mean plus two standard deviations.
    public static func unusual(amount: Decimal, previous: [Decimal]) -> Unusual? {
        guard previous.count >= 3, amount > 0 else { return nil }
        let values = previous.map { NSDecimalNumber(decimal: $0).doubleValue }.sorted()
        let median = values.count.isMultiple(of: 2)
            ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2
            : values[values.count / 2]
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = sqrt(values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count))
        let value = NSDecimalNumber(decimal: amount).doubleValue
        guard median > 0, value > median * 2, value > mean + 2 * deviation else { return nil }
        return Unusual(typical: Decimal(median), times: value / median)
    }
}
