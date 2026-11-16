import Foundation

/// The same card purchase can reach Ghaf twice: once from the Wallet transaction automation and once
/// from the bank's message. Two records are the same purchase only when they came from different
/// sources, match in amount, currency and direction, arrived within `window` of each other, and their
/// merchant names agree when both have one. Two purchases from the same source are never merged, so
/// buying the same coffee twice stays two transactions.
public enum CrossSourceDuplicate {
    public struct Record {
        public let amount: Decimal
        public let currency: String
        public let isDebit: Bool
        public let merchant: String?
        public let arrivedAt: Date
        public let isWallet: Bool
        public init(amount: Decimal, currency: String, isDebit: Bool, merchant: String?, arrivedAt: Date, isWallet: Bool) {
            self.amount = amount; self.currency = currency; self.isDebit = isDebit
            self.merchant = merchant; self.arrivedAt = arrivedAt; self.isWallet = isWallet
        }
    }

    public static let window: TimeInterval = 30 * 60

    public static func isSamePurchase(_ a: Record, _ b: Record) -> Bool {
        guard a.isWallet != b.isWallet, a.amount == b.amount, a.isDebit == b.isDebit,
              a.currency.uppercased() == b.currency.uppercased(),
              abs(a.arrivedAt.timeIntervalSince(b.arrivedAt)) <= window else { return false }
        guard let m1 = a.merchant.map(key), let m2 = b.merchant.map(key), !m1.isEmpty, !m2.isEmpty else { return true }
        // Wallet says "Carrefour", the bank says "CARREFOUR MOE DUBAI": share the leading word or contain each other.
        return m1.contains(m2) || m2.contains(m1) || m1.split(separator: " ").first == m2.split(separator: " ").first
    }

    static func key(_ merchant: String) -> String {
        merchant.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(separator: " ")
    }
}
