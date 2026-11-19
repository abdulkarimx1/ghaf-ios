import Foundation

public enum TransactionEffect {
    public static func spending(amount: Decimal, isDebit: Bool, isReversal: Bool, countsAsSpendingOrIncome: Bool) -> Decimal {
        guard countsAsSpendingOrIncome, isDebit != isReversal else { return 0 }
        return isReversal ? -amount : amount
    }

    public static func income(amount: Decimal, isDebit: Bool, isReversal: Bool, countsAsSpendingOrIncome: Bool) -> Decimal {
        guard countsAsSpendingOrIncome, isDebit == isReversal else { return 0 }
        return isReversal ? -amount : amount
    }
}
