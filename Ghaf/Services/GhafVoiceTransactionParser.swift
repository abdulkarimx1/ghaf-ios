import Foundation

struct GhafVoiceTransactionDraft: Identifiable {
    let id = UUID()
    var merchant: String
    var amount: Decimal
    var currency: String
    var date: Date
    var category: String
    var direction: String
}

enum GhafVoiceTransactionParser {
    private static let amountPattern = #"(?i)(?:\b(?:aed|dhs?|dirhams?|sar|kwd|bhd|omr|qar|usd|eur|gbp)\s*)?([0-9]+(?:[,.][0-9]{1,2})?)\s*(?:\b(?:aed|dhs?|dirhams?|sar|kwd|bhd|omr|qar|usd|eur|gbp)\b|درهم|دراهم|ريال|ريالات|دينار|دنانير|ر\.س|د\.إ)?"#

    static func parse(_ transcript: String, languageCode: String, baseCurrency: String) -> [GhafVoiceTransactionDraft] {
        let separated = transcript
            .replacingOccurrences(of: "،", with: ",")
            .replacingOccurrences(
                of: #"(?i)\b(?:then|and then|after that|also)\b|ثم|وبعدها|بعد ذلك"#,
                with: "|",
                options: .regularExpression
            )
        let parts = separated.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts.compactMap { segment in
            guard let regex = try? NSRegularExpression(pattern: amountPattern),
                  let match = regex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)),
                  let amountRange = Range(match.range(at: 1), in: segment) else { return nil }

            let amountText = String(segment[amountRange]).replacingOccurrences(of: ",", with: ".")
            guard let amount = Decimal(string: amountText), amount > 0 else { return nil }

            let currency = detectCurrency(in: segment) ?? baseCurrency
            var merchant = segment
            merchant.removeSubrange(amountRange)
            merchant = merchant.replacingOccurrences(
                of: #"(?i)\b(?:i|we|just|went|to|the|store|supermarket|bought|buy|got|paid|for|spent|on|at|a|an|dhs?|dirhams?|aed|sar|kwd|bhd|omr|qar|usd|eur|gbp|today|yesterday|this morning|last night)\b"#,
                with: " ",
                options: .regularExpression
            )
            merchant = merchant.replacingOccurrences(
                of: #"درهم|دراهم|ريال|ريالات|دينار|دنانير|اشتريت|اشتريتُ|دفعت|من|في|على|اليوم|أمس|ثم|وبعدها"#,
                with: " ",
                options: .regularExpression
            )
            merchant = merchant.replacingOccurrences(of: #"[,:؛،]"#, with: " ", options: .regularExpression)
            merchant = merchant.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if merchant.isEmpty {
                merchant = languageCode == "ar" ? "عملية صوتية" : "Voice transaction"
            }

            return GhafVoiceTransactionDraft(
                merchant: merchant,
                amount: amount,
                currency: currency,
                date: inferredDate(from: segment),
                category: "Other",
                direction: isIncome(segment) ? "credit" : "debit"
            )
        }
    }

    private static func isIncome(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.range(
            of: #"(?i)\b(?:received|salary|income|deposit|refund|cashback)\b|استلمت|راتب|إيداع|استرداد"#,
            options: .regularExpression
        ) != nil
    }

    private static func detectCurrency(in text: String) -> String? {
        let value = text.lowercased()
        let mappings: [(String, [String])] = [
            ("AED", ["aed", "dhs", "dh", "dirham", "درهم", "د.إ"]),
            ("SAR", ["sar", "riyal", "ريال", "ر.س"]),
            ("KWD", ["kwd", "د.ك", "دينار"]),
            ("BHD", ["bhd", "د.ب"]),
            ("OMR", ["omr", "ر.ع"]),
            ("QAR", ["qar", "ر.ق"]),
            ("USD", ["usd", "dollar"]),
            ("EUR", ["eur", "euro"]),
            ("GBP", ["gbp", "pound"])
        ]
        return mappings.first { _, tokens in tokens.contains(where: { value.contains($0) }) }?.0
    }

    private static func inferredDate(from text: String) -> Date {
        let lower = text.lowercased()
        let calendar = Calendar.current
        var date = Date()
        if lower.contains("yesterday") || lower.contains("أمس") {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }

        let timePattern = #"(?i)\b([0-1]?[0-9])(?::([0-5][0-9]))?\s*(am|pm)\b"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let hourRange = Range(match.range(at: 1), in: text),
           let periodRange = Range(match.range(at: 3), in: text) {
            var hour = Int(text[hourRange]) ?? 0
            let period = text[periodRange].lowercased()
            if period == "pm" && hour < 12 { hour += 12 }
            if period == "am" && hour == 12 { hour = 0 }
            let minute = match.range(at: 2).location == NSNotFound
                ? 0
                : Int(Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? "0") ?? 0
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        return date
    }
}
