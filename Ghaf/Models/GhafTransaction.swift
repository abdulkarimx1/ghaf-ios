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
    /// A purchase made in another currency: what the bank message said, and the market rate Ghaf used
    /// to record it in the account's currency (an estimate; the bank's own rate and fees may differ).
    var originalAmount: Decimal? = nil
    var originalCurrency: String? = nil
    var exchangeRate: Decimal? = nil
    var exchangeRateDate: Date? = nil
    var confidence: Double
    var bank: String?
    var needsReview: Bool
    var isReversal: Bool
    var note: String?
    var createdAt: Date

    /// Moves between the user's own wallets and balance adjustments change balances,
    /// but are never spending or income.
    var isSpendingOrIncome: Bool { category != "Transfers" && category != "Adjustment" }
    /// Purchases, plus refunds/reversals of purchases (credits that offset spending).
    /// shortcut: a reversed credit (debit with isReversal) counts as neither; offset income if that shows up.
    var isExpense: Bool { isSpendingOrIncome && (direction == "debit") != isReversal }
    var isIncome: Bool { direction == "credit" && isSpendingOrIncome && !isReversal }
    /// Signed spending effect: a refund lowers spending and is never income.
    var spendingAmount: Decimal { isExpense ? (isReversal ? -amount : amount) : 0 }

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
