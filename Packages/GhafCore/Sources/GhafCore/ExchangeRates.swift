import Foundation

/// A snapshot of market rates against one base currency, with the time the provider published it.
public struct ExchangeRates: Codable, Equatable, Sendable {
    public let base: String
    public let rates: [String: Decimal]
    public let updated: Date

    public init(base: String, rates: [String: Decimal], updated: Date) {
        self.base = base
        self.rates = rates
        self.updated = updated
    }

    /// Units of `to` for one unit of `from`.
    public func rate(from: String, to: String) -> Decimal? {
        if from == to { return 1 }
        guard let fromRate = rates[from], let toRate = rates[to], fromRate > 0 else { return nil }
        return toRate / fromRate
    }

    /// `amount` in `to`, rounded to cents.
    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        guard let rate = rate(from: from, to: to) else { return nil }
        var value = amount * rate, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }
}
