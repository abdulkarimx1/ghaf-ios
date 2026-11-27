import Foundation

public enum TransactionEffect {
    /// A transfer decision, including `pending`, prevents the Review prompt from recurring.
    public static func shouldAskAboutTransfer(decision: String?) -> Bool { decision == nil }

    /// True only when the ledger explicitly says the recipient is outside the user's accounts.
    public static func isKnownExternalTransferSubcategory(_ value: String?) -> Bool {
        guard let value else { return false }
        let external = CategoryTaxonomy.transferSubcategories.filter { $0.name != "Between my accounts" }
        let keys = external.flatMap { [$0.name, $0.arabic] + $0.words }.map(CategoryMatcher.normalize)
        return keys.contains(CategoryMatcher.normalize(value))
    }

    /// Amount shown in the separate Transfers group, never in expense totals.
    public static func outgoingTransfer(amount: Decimal, isDebit: Bool, isReversal: Bool,
                                        isTransfer: Bool, isBetweenOwnAccounts: Bool) -> Decimal {
        guard isTransfer, isDebit, !isReversal, !isBetweenOwnAccounts else { return 0 }
        return amount
    }

    public static func spending(amount: Decimal, isDebit: Bool, isReversal: Bool, countsAsSpendingOrIncome: Bool) -> Decimal {
        guard countsAsSpendingOrIncome, isDebit != isReversal else { return 0 }
        return isReversal ? -amount : amount
    }

    public static func income(amount: Decimal, isDebit: Bool, isReversal: Bool, countsAsSpendingOrIncome: Bool) -> Decimal {
        guard countsAsSpendingOrIncome, isDebit == isReversal else { return 0 }
        return isReversal ? -amount : amount
    }
}
