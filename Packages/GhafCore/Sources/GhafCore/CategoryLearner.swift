import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// A small on-device classifier that learns categories from the user's own confirmed transactions.
///
/// Multinomial naive Bayes over merchant words, merchant letter trigrams (so "CARREFOUR MOE 12" and
/// "Carrefour" share evidence), amount size, weekday and time of day. It is retrained from the ledger,
/// so every confirmed edit is new training data and nothing is learned from unconfirmed records.
/// Words it has never seen are mapped to the nearest known word with Apple's on-device word
/// embeddings ("latte" → "coffee"), which is how a merchant it never met can still be recognised.
public struct CategoryLearner {

    public struct Sample {
        public let merchant: String
        public let amount: Decimal
        public let date: Date
        public let category: String
        public let subcategory: String?
        public init(merchant: String, amount: Decimal, date: Date, category: String, subcategory: String?) {
            self.merchant = merchant; self.amount = amount; self.date = date
            self.category = category; self.subcategory = subcategory
        }
    }

    public struct Prediction: Equatable {
        public let category: String
        public let subcategory: String?
        /// Posterior probability of the winning category, 0...1.
        public let confidence: Double
    }

    private var featureCounts: [String: [String: Double]] = [:]   // category → feature → count
    private var totalFeatures: [String: Double] = [:]              // category → feature total
    private var classCounts: [String: Double] = [:]
    private var subcategories: [String: [String: Int]] = [:]       // category → subcategory → count
    private var vocabulary: Set<String> = []
    private var knownWords: Set<String> = []
    public private(set) var sampleCount = 0

    public init(samples: [Sample]) {
        for sample in samples { learn(sample) }
    }

    public mutating func learn(_ sample: Sample) {
        let features = Self.features(merchant: sample.merchant, amount: sample.amount, date: sample.date)
        guard !features.isEmpty else { return }
        sampleCount += 1
        classCounts[sample.category, default: 0] += 1
        for feature in features {
            featureCounts[sample.category, default: [:]][feature, default: 0] += 1
            totalFeatures[sample.category, default: 0] += 1
            vocabulary.insert(feature)
            if feature.hasPrefix("w:") { knownWords.insert(String(feature.dropFirst(2))) }
        }
        if let subcategory = sample.subcategory {
            subcategories[sample.category, default: [:]][subcategory, default: 0] += 1
        }
    }

    /// Best category, or nil when there is too little evidence to say.
    public func predict(merchant: String, amount: Decimal, date: Date) -> Prediction? {
        guard sampleCount >= 3, classCounts.count >= 2 else { return nil }
        var features = Self.features(merchant: merchant, amount: amount, date: date)
        // Unknown words borrow evidence from their nearest known word.
        for feature in features where feature.hasPrefix("w:") && !vocabulary.contains(feature) {
            if let near = nearestKnownWord(to: String(feature.dropFirst(2))) { features.append("w:" + near) }
        }
        // Only features seen in training carry evidence; with none, there is nothing learned to apply.
        guard features.contains(where: { vocabulary.contains($0) && !$0.hasPrefix("a:") && !$0.hasPrefix("d:") && !$0.hasPrefix("h:") }) else {
            return nil
        }
        let vocabularySize = Double(vocabulary.count)
        let total = Double(sampleCount)
        var scores: [String: Double] = [:]
        for (category, count) in classCounts {
            var score = log(count / total)
            let counts = featureCounts[category] ?? [:]
            let denominator = (totalFeatures[category] ?? 0) + vocabularySize
            for feature in features where vocabulary.contains(feature) {
                score += log(((counts[feature] ?? 0) + 1) / denominator)
            }
            scores[category] = score
        }
        guard let best = scores.max(by: { $0.value < $1.value }) else { return nil }
        // Softmax over log scores for a calibrated-enough probability.
        let sum = scores.values.reduce(0) { $0 + exp($1 - best.value) }
        let subcategory = subcategories[best.key]?.max { $0.value < $1.value }?.key
        return Prediction(category: best.key, subcategory: subcategory, confidence: 1 / sum)
    }

    /// The prediction as a category match, only when it is at least `minimumConfidence` sure.
    public func match(merchant: String, amount: Decimal, date: Date, minimumConfidence: Double = 0.6) -> CategoryMatcher.Match? {
        guard let prediction = predict(merchant: merchant, amount: amount, date: date),
              prediction.confidence >= minimumConfidence else { return nil }
        return CategoryMatcher.Match(category: prediction.category, subcategory: prediction.subcategory,
                                     confidence: prediction.confidence, source: .model)
    }

    static func features(merchant: String, amount: Decimal, date: Date) -> [String] {
        let text = MerchantName.key(merchant)
        let words: [String] = text.components(separatedBy: " ").filter { $0.count >= 2 && !$0.allSatisfy(\.isNumber) }
        guard !words.isEmpty else { return [] }
        var result = words.map { "w:" + $0 }
        for word in words where word.count >= 4 {
            let letters = Array(word)
            for index in 0...(letters.count - 3) { result.append("t:" + String(letters[index..<index + 3])) }
        }
        let value = max(NSDecimalNumber(decimal: amount).doubleValue, 0.01)
        result.append("a:\(Int(log10(value) * 2))")        // half-decade amount buckets
        let calendar = Calendar(identifier: .gregorian)
        result.append("d:\(calendar.component(.weekday, from: date))")
        result.append("h:\(calendar.component(.hour, from: date) / 6)")
        return result
    }

    private func nearestKnownWord(to word: String) -> String? {
        #if canImport(NaturalLanguage)
        let isArabic = word.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
        guard let embedding = NLEmbedding.wordEmbedding(for: isArabic ? .arabic : .english),
              embedding.contains(word) else { return nil }
        var best: (String, Double)?
        for known in knownWords where embedding.contains(known) {
            let distance = embedding.distance(between: word, and: known)
            if distance < 0.9, distance < (best?.1 ?? .infinity) { best = (known, distance) }
        }
        return best?.0
        #else
        return nil
        #endif
    }
}
