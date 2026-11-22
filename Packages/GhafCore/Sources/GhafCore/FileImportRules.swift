import Foundation

public struct FileImportClassification: Equatable {
    public let direction: TransactionDirection
    public let needsReview: Bool

    public init(direction: TransactionDirection, needsReview: Bool) {
        self.direction = direction
        self.needsReview = needsReview
    }
}

public enum FileImportRules {
    /// Classifies explicit types by complete words so "credit card purchase" remains an expense.
    public static func classification(type: String?, hasTypeColumn: Bool, amount: Decimal,
                                      amountHeader: String, category: String = "") -> FileImportClassification {
        let tokens = Set(typeTokens(type ?? ""))
        let expenseTokens: Set<String> = ["expense", "debit", "purchase", "withdrawal", "payment", "spent", "مصروف", "خصم", "سحب"]
        let incomeTokens: Set<String> = ["income", "credit", "deposit", "salary", "received", "دخل", "إيداع", "ايداع"]
        if !tokens.isDisjoint(with: expenseTokens) { return .init(direction: .debit, needsReview: false) }
        if !tokens.isDisjoint(with: incomeTokens) { return .init(direction: .credit, needsReview: false) }

        let categoryTokens = Set(typeTokens(category))
        if hasTypeColumn && !categoryTokens.isDisjoint(with: ["income", "salary", "deposit", "دخل", "إيداع", "ايداع"]) {
            return .init(direction: .credit, needsReview: false)
        }
        guard !hasTypeColumn else {
            return .init(direction: amount < 0 ? .debit : .credit, needsReview: false)
        }
        if amount < 0 { return .init(direction: .debit, needsReview: false) }
        let headerTokens = Set(typeTokens(amountHeader))
        if !headerTokens.isDisjoint(with: ["income", "credit", "deposit", "دخل", "دائن", "إيداع", "ايداع"]) {
            return .init(direction: .credit, needsReview: false)
        }
        return .init(direction: .debit, needsReview: true)
    }

    /// Only rows with an explicit reference or a time component can be safely deduplicated.
    public static func isDuplicate(reference: String?, hasTime: Bool, date: Date, amount: Decimal,
                                   merchant: String, account: String?, among rows: [FileImportIdentity]) -> Bool {
        let normalizedMerchant = merchantKey(merchant)
        let normalizedReference = reference?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.contains { existing in
            guard existing.amount == amount,
                  merchantKey(existing.merchant) == normalizedMerchant,
                  normalizedAccount(existing.account) == normalizedAccount(account) else { return false }
            if let reference = normalizedReference, !reference.isEmpty,
               let other = existing.reference?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !other.isEmpty,
               reference == other { return true }
            return hasTime && existing.hasTime && existing.date == date
        }
    }

    private static func typeTokens(_ value: String) -> [String] {
        value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func merchantKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalizedAccount(_ value: String?) -> String {
        (value ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct FileImportIdentity: Equatable {
    public let date: Date
    public let hasTime: Bool
    public let amount: Decimal
    public let merchant: String
    public let account: String?
    public let reference: String?

    public init(date: Date, hasTime: Bool, amount: Decimal, merchant: String, account: String?, reference: String?) {
        self.date = date
        self.hasTime = hasTime
        self.amount = amount
        self.merchant = merchant
        self.account = account
        self.reference = reference
    }
}
