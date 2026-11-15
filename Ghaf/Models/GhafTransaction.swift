import Foundation
import SwiftData
import GhafCore

@Model
final class GhafTransaction {
    @Attribute(.unique)
    var fingerprint: String
    var id: UUID
    var amount: Decimal
    var currency: String
    var merchant: String?
    var date: Date
    var direction: String
    var category: String
    var subcategory: String? = nil
    var confidence: Double
    var bank: String?
    var needsReview: Bool
    var isReversal: Bool
    var note: String?
    var createdAt: Date

    /// Moves between the user's own wallets and balance adjustments change balances,
    /// but are never spending or income.
    var isSpendingOrIncome: Bool { category != "Transfers" && category != "Adjustment" }
    var isExpense: Bool { direction == "debit" && isSpendingOrIncome }
    var isIncome: Bool { direction == "credit" && isSpendingOrIncome }

    // A transaction can remain unassigned when its source account is unknown.
    var accountID: UUID?

    init(
        fingerprint: String,
        parsed: ParsedTransaction,
        category: String,
        needsReview: Bool,
        isReversal: Bool,
        accountID: UUID? = nil
    ) {
        self.fingerprint = fingerprint
        self.id = UUID()
        self.amount = parsed.amount
        self.currency = parsed.currency
        self.merchant = parsed.merchant
        self.date = parsed.date
        self.direction = parsed.direction.rawValue
        self.category = category
        self.confidence = parsed.confidence
        self.bank = parsed.bank
        self.needsReview = needsReview
        self.isReversal = isReversal
        self.note = nil
        self.createdAt = .now
        self.accountID = accountID
    }
}
