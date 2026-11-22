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

    /// Suggests the most specific built-in category for a subscription name or merchant description.
    /// It reuses the shared bilingual taxonomy, so gym, clinic, insurance and home services keep
    /// their expense category instead of being filed under the generic Subscriptions bucket.
    public static func suggestedCategory(for merchant: String) -> CategoryMatcher.Match? {
        let catalog = Dictionary(uniqueKeysWithValues: CategoryTaxonomy.all.map { ($0.name, $0.subcategories.map(\.name)) })
        return CategoryMatcher.match(merchant, catalog: catalog, learned: [:])
    }

    /// Keeps service punctuation and removes trailing reference digits.
    public static func normalize(_ merchant: String) -> String {
        let withoutReference = merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+\d+$"#, with: "", options: .regularExpression)
        return String(withoutReference.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "/" || CharacterSet.whitespacesAndNewlines.contains(scalar) ? Character(scalar) : " "
        }).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Same service when the names match after `normalize`, or the charge's merchant starts with the
    /// subscription name as a whole word ("NETFLIX.COM 8829" pays "Netflix", "Netflixer" does not).
    /// Spaces are ignored ("CHATGPT" pays "Chat GPT") and the name may start at any word of the charge
    /// ("OPENAI *CHATGPT SUBSCR" pays "ChatGPT").
    public static func sameService(merchant: String, subscriptionName: String) -> Bool {
        let words = normalize(merchant).split(separator: " ").map(String.init)
        let name = normalize(subscriptionName).replacingOccurrences(of: " ", with: "")
        guard name.count >= 3 else { return false }
        for start in words.indices {
            var joined = ""
            for word in words[start...] {
                joined += word
                if joined.hasPrefix(name) {
                    // Whole words only: "Netflixer" is not "Netflix", "netflix.com" is.
                    if joined.dropFirst(name.count).first.map({ !$0.isLetter }) ?? true { return true }
                    break
                }
                if !name.hasPrefix(joined) { break }
            }
        }
        return false
    }

    /// A charge pays a subscription due on `dueDate` when it is the same service, its amount is
    /// within 10% and it lands within `toleranceDays` of the due date. Services can bill early.
    public static func isPayment(
        merchant: String?, amount: Decimal, date: Date,
        subscriptionName: String, subscriptionAmount: Decimal, dueDate: Date, toleranceDays: Int
    ) -> Bool {
        guard let merchant, sameService(merchant: merchant, subscriptionName: subscriptionName),
              isSimilar(amount, subscriptionAmount) else { return false }
        return withinWindow(date, of: dueDate, toleranceDays: toleranceDays)
    }

    /// The new price when a charge for the same service, inside the due window, costs more than the
    /// set price: a price rise to offer the user. Over 3x is likely a different purchase, so it's ignored.
    public static func raisedPrice(
        merchant: String?, amount: Decimal, date: Date,
        subscriptionName: String, subscriptionAmount: Decimal, dueDate: Date, toleranceDays: Int
    ) -> Decimal? {
        guard let merchant, sameService(merchant: merchant, subscriptionName: subscriptionName),
              amount - subscriptionAmount > Decimal(string: "0.01")!, amount <= subscriptionAmount * 3,
              withinWindow(date, of: dueDate, toleranceDays: toleranceDays) else { return nil }
        return amount
    }

    private static func withinWindow(_ date: Date, of dueDate: Date, toleranceDays: Int) -> Bool {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: dueDate),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? .max
        let earlyDays = toleranceDays <= 2 ? toleranceDays : max(toleranceDays, 15)
        return days >= -earlyDays && days <= toleranceDays
    }

    static func isSimilar(_ a: Decimal, _ b: Decimal) -> Bool {
        let diff = abs(NSDecimalNumber(decimal: a - b).doubleValue)
        return diff <= max(NSDecimalNumber(decimal: b).doubleValue * 0.10, 0.01)
    }
}
