import Foundation

/// Decides whether a debit from a bank message looks like a subscription charge.
public enum SubscriptionDetector {

    public enum Cycle: String { case weekly, monthly, yearly }

    public struct PastCharge {
        public let merchant: String
        public let amount: Decimal
        public let date: Date
        public init(merchant: String, amount: Decimal, date: Date) {
            self.merchant = merchant
            self.amount = amount
            self.date = date
        }
    }

    /// Lower-case fragments of merchant names that are almost always recurring services.
    static let knownServices = [
        "netflix", "spotify", "apple.com/bill", "itunes", "icloud", "youtube", "google one",
        "google storage", "shahid", "osn", "anghami", "starzplay", "amazon prime", "prime video",
        "disney", "openai", "chatgpt", "anthropic", "claude.ai", "adobe", "microsoft", "xbox",
        "playstation", "nintendo", "dropbox", "canva", "notion", "linkedin", "patreon", "deezer",
        "tidal", "crunchyroll", "audible", "kindle unlimited", "duolingo", "headspace", "calm",
        "careem plus", "noon one", "talabat pro", "deliveroo plus", "gym", "fitness first"
    ]

    /// Returns the billing cycle when `merchant` charged `amount` like a subscription, else nil.
    /// A known service counts on its first charge; any other merchant needs an earlier charge of a
    /// similar amount (within 10%) roughly one week, one month or one year before `date`.
    public static func detect(
        merchant: String?,
        amount: Decimal,
        date: Date,
        history: [PastCharge]
    ) -> Cycle? {
        guard let merchant, amount > 0 else { return nil }
        let key = normalize(merchant)
        guard !key.isEmpty else { return nil }

        for past in history where normalize(past.merchant) == key && isSimilar(past.amount, amount) {
            let days = Calendar.current.dateComponents([.day], from: past.date, to: date).day ?? 0
            switch days {
            case 6...8: return .weekly
            case 26...35: return .monthly
            case 355...375: return .yearly
            default: continue
            }
        }

        if knownServices.contains(where: { key.contains($0) }) { return .monthly }
        return nil
    }

    /// Merchant name without digits, punctuation or extra spaces, so "NETFLIX.COM 8829" == "Netflix.com".
    public static func normalize(_ merchant: String) -> String {
        merchant.lowercased()
            .filter { $0.isLetter || $0 == " " || $0 == "." || $0 == "/" }
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Same service when the names match after `normalize`, or the charge's merchant starts with the
    /// subscription name as a whole word ("NETFLIX.COM 8829" pays "Netflix", "Netflixer" does not).
    public static func sameService(merchant: String, subscriptionName: String) -> Bool {
        let charge = normalize(merchant), name = normalize(subscriptionName)
        guard name.count >= 3, charge.hasPrefix(name) else { return false }
        return charge.dropFirst(name.count).first.map { !$0.isLetter } ?? true
    }

    /// A charge pays a subscription due on `dueDate` when it is the same service, its amount is
    /// within 10% and it lands within `toleranceDays` of the due date.
    public static func isPayment(
        merchant: String?, amount: Decimal, date: Date,
        subscriptionName: String, subscriptionAmount: Decimal, dueDate: Date, toleranceDays: Int
    ) -> Bool {
        guard let merchant, sameService(merchant: merchant, subscriptionName: subscriptionName),
              isSimilar(amount, subscriptionAmount) else { return false }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: dueDate),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? .max
        return abs(days) <= toleranceDays
    }

    static func isSimilar(_ a: Decimal, _ b: Decimal) -> Bool {
        let diff = abs(NSDecimalNumber(decimal: a - b).doubleValue)
        return diff <= max(NSDecimalNumber(decimal: b).doubleValue * 0.10, 0.01)
    }
}
