import Foundation

/// Spots corrections such as "no, edit karak it was 5 dhs" or "لا، الكرك كان ٥" so the chat updates
/// an earlier entry instead of logging a new one.
public enum ChatCorrection {

    public struct Result: Equatable {
        /// Index into the `recent` names passed in (0 = most recent).
        public let index: Int
        public let amount: Decimal?
    }

    private static let cues = ["no", "nope", "edit", "change", "actually", "correct", "correction", "wrong", "update", "make it",
                               "it was", "it is", "its", "لا", "عدل", "غير", "صحح", "كان", "كانت", "خله", "خليه", "مو", "مب", "الصح", "تعديل"]
    private static let filler: Set<String> = ["no", "nope", "edit", "change", "actually", "correct", "correction", "wrong", "update",
                                              "make", "it", "was", "is", "its", "the", "to", "please", "dhs", "dh", "aed", "dirham", "dirhams",
                                              "sar", "riyal", "riyals", "kwd", "qar", "bhd", "omr", "لا", "عدل", "غير", "صحح", "كان", "كانت",
                                              "خله", "خليه", "مو", "مب", "الصح", "تعديل", "درهم", "دراهم", "ريال", "دينار", "بس", "يعني"]

    /// `recent` are merchant names of the latest entries, most recent first.
    public static func parse(_ text: String, recent: [String]) -> Result? {
        let spoken = NumberWords.replace(in: GhafVoiceTransactionParser.normalizeNumerals(text))
        let key = CategoryMatcher.normalize(spoken)
        let padded = " \(key) "
        guard cues.contains(where: { padded.hasPrefix(" \($0) ") || ($0.contains(" ") || $0 == "كان") && padded.contains(" \($0) ") })
        else { return nil }

        let amount = spoken.range(of: #"[0-9]+(?:[.,][0-9]{1,2})?"#, options: .regularExpression)
            .flatMap { Decimal(string: spoken[$0].replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) }
        let words = key.split(separator: " ").map { stripArticle(String($0)) }

        // A recent entry whose name is mentioned ("karak", "الكرك").
        if let index = recent.firstIndex(where: { name in
            let parts = CategoryMatcher.normalize(name).split(separator: " ").map { stripArticle(String($0)) }.filter { $0.count >= 3 }
            return !parts.isEmpty && parts.allSatisfy(words.contains)
        }) {
            return Result(index: index, amount: amount)
        }
        // "no, it was 7": nothing but cue words and a number → the latest entry.
        let leftover = words.filter { !filler.contains($0) && $0.rangeOfCharacter(from: .decimalDigits) == nil }
        if leftover.isEmpty, amount != nil, !recent.isEmpty {
            return Result(index: 0, amount: amount)
        }
        return nil
    }

    private static func stripArticle(_ word: String) -> String {
        word.hasPrefix("ال") && word.count > 4 ? String(word.dropFirst(2)) : word
    }
}
