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

    public enum Source: Equatable { case learned, name, synonym, model }

    public struct Match: Equatable {
        public let category: String
        public let subcategory: String?
        public let confidence: Double
        public let source: Source
        /// The user doesn't have this category yet; offer to create it.
        public var isNewCategory = false
        /// The category exists but this subcategory doesn't yet.
        public var isNewSubcategory = false
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
            // "car rental": the category is named, a built-in word can still pick the subcategory.
            if let hit = taxonomyHit(padded), case let refined = resolve(hit.category, hit.sub, in: catalog),
               refined.category == category {
                return refined
            }
            return Match(category: category, subcategory: nil, confidence: 0.75, source: .name)
        }

        // 3. Built-in GCC words (exact, then one-typo fuzzy), mapped onto the user's own names.
        guard let hit = taxonomyHit(padded) ?? fuzzyTaxonomyHit(key) else { return nil }
        return resolve(hit.category, hit.sub, in: catalog)
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
        return !word.isEmpty && containsToken(padded, word)
    }

    private static func containsToken(_ padded: String, _ word: String) -> Bool {
        padded.contains(" \(word) ") || padded.contains(" ال\(word) ")
    }

    private typealias Hit = (category: CategoryTaxonomy.Category, sub: CategoryTaxonomy.Subcategory)

    /// Longest built-in keyword found as whole words in the text.
    private static func taxonomyHit(_ padded: String) -> Hit? {
        var best: (hit: Hit, length: Int)?
        for category in CategoryTaxonomy.all {
            for sub in category.subcategories {
                for word in sub.words {
                    let key = normalize(word)
                    guard !key.isEmpty, containsToken(padded, key), key.count > (best?.length ?? 0) else { continue }
                    best = ((category, sub), key.count)
                }
            }
        }
        return best?.hit
    }

    /// Tolerates one typo in a single word ("zuba" → "zumba"), only for keywords of 5+ letters.
    private static func fuzzyTaxonomyHit(_ key: String) -> Hit? {
        let words = key.split(separator: " ").map(String.init).filter { $0.count >= 4 }
        for category in CategoryTaxonomy.all {
            for sub in category.subcategories {
                for keyword in sub.words.map(normalize) where keyword.count >= 5 && !keyword.contains(" ") {
                    if words.contains(where: { isOneEditAway($0, keyword) }) { return (category, sub) }
                }
            }
        }
        return nil
    }

    /// Finds the user's version of a built-in category/subcategory, or marks it as new.
    private static func resolve(_ category: CategoryTaxonomy.Category, _ sub: CategoryTaxonomy.Subcategory,
                                in catalog: [String: [String]]) -> Match {
        let names = Set(([category.name] + category.aliases).map(normalize))
        let userCategory = catalog.keys.sorted().first { names.contains(normalize($0)) }
            // e.g. the user's "Car" holds "Fuel" even if called something else
            ?? catalog.first { $0.value.contains { normalize($0) == normalize(sub.name) } }?.key
        guard let userCategory else {
            var match = Match(category: category.name, subcategory: sub.name, confidence: 0.5, source: .synonym)
            match.isNewCategory = true
            return match
        }
        let subWords = Set(([sub.name] + sub.words).map(normalize))
        if let userSub = catalog[userCategory]?.first(where: { subWords.contains(normalize($0)) }) {
            return Match(category: userCategory, subcategory: userSub, confidence: 0.65, source: .synonym)
        }
        var match = Match(category: userCategory, subcategory: sub.name, confidence: 0.55, source: .synonym)
        match.isNewSubcategory = true
        return match
    }

    static func isOneEditAway(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 1, a != b else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count { i += 1 } else if a.count < b.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }
}
