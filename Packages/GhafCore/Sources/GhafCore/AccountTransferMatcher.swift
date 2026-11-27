import Foundation

public enum AccountTransferMatcher {
    public struct Candidate: Equatable {
        public let id: UUID
        public let accountID: UUID?
        public let amount: Decimal
        public let currency: String
        public let date: Date
        public let direction: String
        public let isReversal: Bool
        public let hasTransferEvidence: Bool
        public init(id: UUID, accountID: UUID?, amount: Decimal, currency: String, date: Date,
                    direction: String, isReversal: Bool, hasTransferEvidence: Bool) {
            self.id = id; self.accountID = accountID; self.amount = amount; self.currency = currency
            self.date = date; self.direction = direction; self.isReversal = isReversal
            self.hasTransferEvidence = hasTransferEvidence
        }
    }
    public struct Pair: Equatable {
        public let debitID: UUID
        public let creditID: UUID
        public var key: String { [debitID.uuidString, creditID.uuidString].sorted().joined(separator: ":") }
    }

    /// Pairs each credit to the nearest eligible debit once; stable IDs make reruns idempotent.
    public static func pairs(in candidates: [Candidate], alreadyPaired: Set<String> = []) -> [Pair] {
        let ordered = candidates.filter { $0.hasTransferEvidence && !$0.isReversal && $0.accountID != nil }
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
        var used = alreadyPaired
        var usedIDs = Set(alreadyPaired.flatMap { $0.split(separator: ":").map(String.init) })
        var pairs: [Pair] = []
        for credit in ordered where credit.direction == "credit" {
            guard !usedIDs.contains(credit.id.uuidString) else { continue }
            let options = ordered.filter { debit in
                guard debit.direction == "debit", debit.accountID != credit.accountID,
                      debit.currency.uppercased() == credit.currency.uppercased(), debit.amount == credit.amount,
                      abs(debit.date.timeIntervalSince(credit.date)) <= 3 * 86_400 else { return false }
                return !usedIDs.contains(debit.id.uuidString) && !used.contains(Pair(debitID: debit.id, creditID: credit.id).key)
            }
            guard let debit = options.min(by: {
                let left = abs($0.date.timeIntervalSince(credit.date)), right = abs($1.date.timeIntervalSince(credit.date))
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }) else { continue }
            let pair = Pair(debitID: debit.id, creditID: credit.id)
            used.insert(pair.key); usedIDs.insert(pair.debitID.uuidString); usedIDs.insert(pair.creditID.uuidString); pairs.append(pair)
        }
        return pairs
    }
}
