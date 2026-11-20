import Foundation

public struct AccountCandidate {
    public let id: UUID
    public let name: String
    public let institution: String?
    public let isBankAccount: Bool
    public let isPrimary: Bool

    public init(id: UUID, name: String, institution: String?, isBankAccount: Bool, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.institution = institution
        self.isBankAccount = isBankAccount
        self.isPrimary = isPrimary
    }
}

public enum AccountMatcher {
    public static func match(bank: String?, sender: String?, candidates: [AccountCandidate]) -> UUID? {
        let incoming = [bank, sender].compactMap { $0 }.map(normalize).filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return nil }
        let ranked = candidates.map { candidate -> (AccountCandidate, Int) in
            let names = [(candidate.institution, 100), (Optional(candidate.name), candidate.isBankAccount ? 100 : 95)]
            let score = incoming.reduce(0) { best, value in
                max(best, names.reduce(0) { current, item in
                    guard let raw = item.0 else { return current }
                    let target = normalize(raw)
                    guard !target.isEmpty else { return current }
                    if value == target { return max(current, item.1) }
                    let partial = min(value.count, target.count) >= 4 && (value.contains(target) || target.contains(value))
                    return partial ? max(current, 60) : current
                })
            }
            return (candidate, score)
        }
        guard let top = ranked.map(\.1).max(), top > 0 else { return nil }
        let tied = ranked.filter { $0.1 == top }.map(\.0)
        if top == 60 { return nil }
        if tied.count == 1 { return tied[0].id }
        let primary = tied.filter(\.isPrimary)
        return primary.count == 1 ? primary[0].id : nil
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
