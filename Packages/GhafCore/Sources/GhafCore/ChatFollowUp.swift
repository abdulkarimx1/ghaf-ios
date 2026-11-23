import Foundation

/// Turns a short follow-up ("and last month?", "what about food?", "وأمس؟") into a full question by
/// carrying over what the previous question was about. A message that already stands on its own
/// is returned unchanged.
public enum ChatFollowUp {

    /// Short, useful next questions selected from the answer topic. These are phrased as
    /// local ledger queries so the UI can answer them without another model request.
    public static func suggestions(after question: String, languageCode: String) -> [String] {
        let text = question.lowercased()
        let ar = languageCode == "ar"
        if ["subscription", "اشتراك"].contains(where: text.contains) {
            return ar ? ["الاشتراكات القادمة", "التكلفة السنوية", "أعلى فئة"]
                      : ["Due subscriptions", "Annual cost", "Top category"]
        }
        if ["balance", "account", "رصيد", "حساب"].contains(where: text.contains) {
            return ar ? ["هذا الشهر والماضي", "أعلى فئة", "الاشتراكات القادمة"]
                      : ["This month vs last", "Top category", "Due subscriptions"]
        }
        return ar ? ["هذا الشهر والماضي", "أعلى فئة", "الاشتراكات القادمة"]
                  : ["This month vs last", "Top category", "Due subscriptions"]
    }

    /// Maps a displayed chip to a deterministic ledger question.
    public static func ledgerQuestion(for suggestion: String, languageCode: String) -> String? {
        let ar = languageCode == "ar"
        switch suggestion {
        case "This month vs last", "هذا الشهر والماضي", "مقارنة هذا الشهر بالماضي": return ar ? "قارن إنفاقي هذا الشهر بالشهر الماضي" : "Compare my spending this month with last month"
        case "Top category", "أعلى فئة", "أعلى فئة إنفاقًا": return ar ? "ما أكثر فئة صرفت فيها هذا الشهر؟" : "What was my top spending category this month?"
        case "Due subscriptions", "الاشتراكات القادمة", "ما موعد الدفع القادم؟": return ar ? "ما الاشتراكات القادمة؟" : "Which subscriptions are due soon?"
        case "Annual subscription cost", "Annual cost", "التكلفة السنوية", "كم تكلف سنويًا؟": return ar ? "كم تبلغ تكلفة اشتراكاتي سنويًا؟" : "What is my annual subscription cost?"
        case "كم صرفت هذا الشهر؟": return "كم صرفت هذا الشهر؟"
        default: return nil
        }
    }

    private static let periodPhrases = [
        "last month", "this month", "last week", "this week", "today", "yesterday", "this year",
        "الشهر الماضي", "هذا الشهر", "هالشهر", "الأسبوع الماضي", "الاسبوع الماضي", "هذا الأسبوع", "هالأسبوع",
        "اليوم", "أمس", "امس", "هذه السنة", "هالسنة"
    ]

    private static let openers = [
        "and ", "what about ", "how about ", "same for ", "for ", "in ", "only ", "what's ", "what is ",
        "و", "طيب ", "وماذا عن ", "وش عن ", "شو عن ", "ماذا عن ", "عن "
    ]

    /// Words that make a question complete on its own.
    private static let intentWords = [
        "spend", "spent", "income", "balance", "subscri", "biggest", "compare", "forecast", "tip", "save",
        "where", "most", "categor", "how much", "chart",
        "صرف", "دخل", "رصيد", "اشتراك", "أكبر", "قارن", "توقع", "نصيحة", "وفر", "وين", "أكثر", "كم", "رسم"
    ]

    public static func resolve(_ message: String, previous: String?) -> String {
        guard let previous, !previous.isEmpty else { return message }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: \.isWhitespace)
        let opens = openers.contains { lower.hasPrefix($0) }
        let namesPeriod = periodPhrases.contains { lower.contains($0) }
        // Only short messages without their own intent, that open like a follow-up or just name a period.
        guard words.count <= 6, !intentWords.contains(where: { lower.contains($0) }), opens || namesPeriod else { return message }

        let core = stripOpener(lower).trimmingCharacters(in: CharacterSet(charactersIn: "?؟.! "))
        var base = previous.lowercased()
        // A new period replaces the old one; anything else (a category, a store) is added.
        if periodPhrases.contains(where: { core.contains($0) }) {
            for phrase in periodPhrases.sorted(by: { $0.count > $1.count }) {
                base = base.replacingOccurrences(of: phrase, with: "")
            }
        }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "?؟.! "))
        return "\(base) \(core)".replacingOccurrences(of: "  ", with: " ")
    }

    private static func stripOpener(_ text: String) -> String {
        for opener in openers.sorted(by: { $0.count > $1.count }) where text.hasPrefix(opener) {
            return String(text.dropFirst(opener.count))
        }
        return text
    }
}
