import Foundation

/// Picks a category and subcategory for free text ("adnoc 120", "lunch", "بنزين") using, in order:
/// what the user taught Ghaf, their own category/subcategory names, then built-in concept synonyms
/// mapped onto whatever the user called that concept.
public enum CategoryMatcher {

    public struct Rule: Equatable, Codable {
        public var category: String
        public var subcategory: String?
        public var hits: Int
        public init(category: String, subcategory: String?, hits: Int) {
            self.category = category
            self.subcategory = subcategory
            self.hits = hits
        }
    }

    public struct Example {
        public let merchant: String
        public let category: String
        public let subcategory: String?
        public init(merchant: String, category: String, subcategory: String?) {
            self.merchant = merchant
            self.category = category
            self.subcategory = subcategory
        }
    }

    public enum Source: Equatable { case learned, name, synonym }

    public struct Match: Equatable {
        public let category: String
        public let subcategory: String?
        public let confidence: Double
        public let source: Source
    }

    /// `catalog` is category name → subcategory names. `learned` is keyed by `normalize(merchant)`.
    public static func match(_ text: String, catalog: [String: [String]], learned: [String: Rule]) -> Match? {
        let key = normalize(text)
        guard !key.isEmpty else { return nil }
        let padded = " \(key) "

        // 1. Exact learned merchant, then a learned merchant mentioned inside the text (longest wins).
        if let rule = learned[key] {
            return Match(category: rule.category, subcategory: rule.subcategory, confidence: 1, source: .learned)
        }
        if let (_, rule) = learned
            .filter({ $0.key.count >= 3 && padded.contains(" \($0.key) ") })
            .max(by: { ($0.key.count, $0.value.hits) < ($1.key.count, $1.value.hits) }) {
            return Match(category: rule.category, subcategory: rule.subcategory, confidence: 0.9, source: .learned)
        }

        // 2. The user's own subcategory names, then category names, as whole words.
        for (category, subs) in catalog.sorted(by: { $0.key < $1.key }) {
            if let sub = subs.first(where: { contains(padded, $0) }) {
                return Match(category: category, subcategory: sub, confidence: 0.85, source: .name)
            }
        }
        if let category = catalog.keys.sorted().first(where: { contains(padded, $0) }) {
            return Match(category: category, subcategory: nil, confidence: 0.75, source: .name)
        }

        // 3. Concept synonyms, resolved to the user's own category/subcategory names.
        for concept in concepts where concept.words.contains(where: { padded.contains(" \($0) ") }) {
            if let found = resolve(concept, in: catalog) {
                return Match(category: found.category, subcategory: found.subcategory, confidence: 0.6, source: .synonym)
            }
        }
        return nil
    }

    /// Builds rules from past transactions: the most common category/subcategory per merchant.
    public static func learn(from history: [Example]) -> [String: Rule] {
        var votes: [String: [String: (category: String, subcategory: String?, count: Int)]] = [:]
        for item in history where item.category != "Other" {
            let key = normalize(item.merchant)
            guard !key.isEmpty else { continue }
            let vote = "\(item.category)|\(item.subcategory ?? "")"
            votes[key, default: [:]][vote, default: (item.category, item.subcategory, 0)].count += 1
        }
        return votes.compactMapValues { options in
            let total = options.values.reduce(0) { $0 + $1.count }
            guard let best = options.values.max(by: { $0.count < $1.count }) else { return nil }
            return Rule(category: best.category, subcategory: best.subcategory, hits: total)
        }
    }

    /// Lower-case words separated by single spaces, accents and punctuation removed.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    // MARK: Private

    private static func contains(_ padded: String, _ name: String) -> Bool {
        let word = normalize(name)
        return !word.isEmpty && padded.contains(" \(word) ")
    }

    private struct Concept {
        let categoryNames: [String]   // what users tend to call the category
        let subcategoryNames: [String]
        let words: [String]           // normalized trigger words, English and Arabic
    }

    private static func resolve(_ concept: Concept, in catalog: [String: [String]]) -> (category: String, subcategory: String?)? {
        let wanted = Set(concept.categoryNames.map(normalize))
        // A subcategory with a concept name (e.g. "Fuel" under "Car") is the most specific answer.
        for (category, subs) in catalog.sorted(by: { $0.key < $1.key }) {
            if let sub = subs.first(where: { concept.subcategoryNames.map(normalize).contains(normalize($0)) }) {
                return (category, sub)
            }
        }
        if let category = catalog.keys.sorted().first(where: { wanted.contains(normalize($0)) }) {
            return (category, nil)
        }
        return nil
    }

    private static let concepts: [Concept] = [
        Concept(categoryNames: ["Car", "Transport", "Transportation", "Fuel"], subcategoryNames: ["Fuel", "Petrol"],
                words: ["petrol", "fuel", "gas", "adnoc", "enoc", "eppco", "emarat", "بنزين", "وقود", "ادنوك"]),
        Concept(categoryNames: ["Car", "Transport", "Transportation"], subcategoryNames: ["Parking"],
                words: ["parking", "mawaqif", "rta", "salik", "باركينغ", "مواقف", "سالك"]),
        Concept(categoryNames: ["Transport", "Transportation", "Car"], subcategoryNames: ["Taxi"],
                words: ["taxi", "uber", "careem", "metro", "bus", "تاكسي", "كريم", "اوبر", "مترو"]),
        Concept(categoryNames: ["Food", "Dining", "Restaurants"], subcategoryNames: ["Lunch", "Dinner", "Breakfast", "Cafeteria", "Coffee"],
                words: ["restaurant", "shawarma", "burger", "pizza", "coffee", "cafe", "karak", "breakfast", "lunch", "dinner",
                        "talabat", "deliveroo", "noon food", "mcdonalds", "kfc", "starbucks", "tim hortons",
                        "مطعم", "شاورما", "قهوة", "كرك", "غداء", "عشاء", "فطور", "طلبات"]),
        Concept(categoryNames: ["Grocery", "Groceries", "Supermarket"], subcategoryNames: [],
                words: ["grocery", "groceries", "supermarket", "carrefour", "lulu", "spinneys", "nesto", "coop", "union coop",
                        "بقالة", "كارفور", "لولو", "جمعية"]),
        Concept(categoryNames: ["Utilities", "Bills & Utilities", "Bills"], subcategoryNames: ["Du", "Etisalat", "Electricity", "Water"],
                words: ["dewa", "sewa", "addc", "etisalat", "e&", "du", "electricity", "water", "internet", "كهرباء", "ماء", "انترنت", "اتصالات"]),
        Concept(categoryNames: ["Subscriptions"], subcategoryNames: [],
                words: ["netflix", "spotify", "icloud", "youtube", "shahid", "osn", "anghami", "chatgpt", "openai", "adobe", "subscription", "اشتراك"]),
        Concept(categoryNames: ["Health & Wellness", "Health", "Medical"], subcategoryNames: ["Medicine", "Barber", "Pharmacy"],
                words: ["pharmacy", "medicine", "doctor", "clinic", "hospital", "barber", "gym", "صيدلية", "دواء", "عيادة", "مستشفى", "حلاق"]),
        Concept(categoryNames: ["Shopping"], subcategoryNames: ["Gifts", "Clothes"],
                words: ["amazon", "noon", "mall", "clothes", "shoes", "gift", "ikea", "namshi", "shein", "تسوق", "ملابس", "هدية"]),
        Concept(categoryNames: ["Entertainment"], subcategoryNames: ["Cinema", "Games"],
                words: ["cinema", "vox", "movie", "game", "playstation", "billiards", "padel", "paddle", "سينما", "لعبة"]),
        Concept(categoryNames: ["Travel"], subcategoryNames: ["Flights", "Hotel"],
                words: ["flight", "emirates", "flydubai", "air arabia", "etihad", "hotel", "booking", "airbnb", "طيران", "فندق"])
    ]
}
