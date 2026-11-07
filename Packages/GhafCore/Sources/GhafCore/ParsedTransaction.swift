import Foundation

public enum TransactionDirection: String, Codable, CaseIterable {
    case debit
    case credit
}

public struct ParsedTransaction: Codable, Equatable {

    public let amount: Decimal
    public let currency: String
    public let merchant: String?
    public let date: Date
    public let direction: TransactionDirection
    public let confidence: Double
    public let bank: String?

    public init(
        amount: Decimal,
        currency: String,
        merchant: String?,
        date: Date,
        direction: TransactionDirection,
        confidence: Double,
        bank: String?
    ) {
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.date = date
        self.direction = direction
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.bank = bank
    }
}
