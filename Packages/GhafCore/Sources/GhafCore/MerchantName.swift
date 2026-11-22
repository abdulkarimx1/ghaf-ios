import Foundation

/// Normalises bank supplied merchant labels without changing their original casing.
public enum MerchantName {
    private static let weekdays = #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|الأحد|الاثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت)"#
    private static let months = #"(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec|يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر|كانون\s+(?:الثاني|الثانية|الأول|الاول)|شباط|آذار|اذار|نيسان|أيار|ايار|حزيران|تموز|آب|اب|أيلول|ايلول|تشرين\s+(?:الأول|الاول|الثاني))"#
    private static let digit = #"[0-9٠-٩۰-۹]"#
    private static let numericDate = #"(?:[0-9٠-٩۰-۹]{1,4}[/-][0-9٠-٩۰-۹]{1,2}(?:[/-][0-9٠-٩۰-۹]{2,4})?|[0-9٠-٩۰-۹]{4}-[0-9٠-٩۰-۹]{1,2}-[0-9٠-٩۰-۹]{1,2})"#
    private static let time = #"(?:[0-9٠-٩۰-۹]{1,2}:[0-9٠-٩۰-۹]{2}(?::[0-9٠-٩۰-۹]{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)"#

    /// Compiled once: building this regex per call made Stats and lists take seconds with ~1,000 transactions.
    private static let tailRegex: NSRegularExpression? = {
        let prep = #"(?:on|at|dated|بتاريخ|في|يوم)\s+"#
        let word = "(?![\\p{L}])"
        let dated = "(?:" + prep + "(?:" + weekdays + "|" + months + ")" + word
            + "|(?:" + prep + ")?(?:" + weekdays + word + #"[\s,]+(?="# + digit + ")"
            + "|" + months + word + #"\s*(?="# + digit + ")"
            + "|" + digit + #"{1,2}\s+"# + months + word
            + "|" + numericDate + "(?!" + digit + ")"
            + "|" + time + "))"
        let noise = #"(?:(?:using|via)\s+(?:[\p{L}\d-]+\s+){0,4}?(?:card|account)\b|باستخدام\s+بطاقة|card\s+ending|ending\s+with|xx[0-9*]|ref\b|auth\b|avl\.?\s*bal\b|available\s+balance\b)"#
        return try? NSRegularExpression(pattern: #"\s+(?:"# + dated + "|" + noise + ").*$", options: [.caseInsensitive])
    }()
    /// `clean` is a pure function of its input, so results are memoised (thread-safe NSCache).
    private static let cleanCache = NSCache<NSString, NSString>()

    public static func clean(_ raw: String) -> String {
        if let hit = cleanCache.object(forKey: raw as NSString) { return hit as String }
        let result = uncachedClean(raw)
        cleanCache.setObject(result as NSString, forKey: raw as NSString)
        return result
    }

    private static func uncachedClean(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A weekday or month only counts as a date after a preposition or next to a number, and only as a whole
        // word, so names like "AL MAYA", "DUBAI MARINA" or "ابو علي" stay intact (see tailRegex).
        if let regex = tailRegex {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if let match = regex.firstMatch(in: value, range: range), let swiftRange = Range(match.range, in: value) {
                value.removeSubrange(swiftRange)
            }
        }
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if value.range(of: #"(?i)\s+CAFET$"#, options: .regularExpression) != nil {
            value = value.replacingOccurrences(of: #"(?i)\s+CAFET$"#, with: "", options: .regularExpression)
        }
        if value.range(of: #"(?i)^(?:on|at|dated|بتاريخ|في|يوم)$"#, options: .regularExpression) != nil {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }

    public static func expand(_ name: String, known: [String]) -> String {
        func prefixForm(_ value: String) -> String {
            clean(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
                .lowercased().filter(\.isLetter)
        }
        let compact = prefixForm(name)
        if compact.count >= 8 {
            let matches = known.filter { prefixForm($0).hasPrefix(compact) }
            let distinct = Set(matches.map(prefixForm))
            if distinct.count == 1, let best = matches.max(by: { $0.count < $1.count }) { return best }
            if distinct.count > 1 {
                let ordered = distinct.sorted { $0.count < $1.count }
                if ordered.dropFirst().enumerated().allSatisfy({ index, value in value.hasPrefix(ordered[index]) }) {
                    return matches.max { left, right in
                        let leftCount = matches.filter { prefixForm($0) == prefixForm(left) }.count
                        let rightCount = matches.filter { prefixForm($0) == prefixForm(right) }.count
                        return leftCount == rightCount ? left.count < right.count : leftCount < rightCount
                    } ?? name
                }
                return name
            }
        }
        let words = name.split(separator: " ").map(String.init)
        guard let last = words.last else { return name }
        let candidates = ["CAFETERIA", "RESTAURANT", "SUPERMARKET", "HYPERMARKET", "TRADING", "PHARMACY", "GROCERY", "ELECTRONICS", "LAUNDRY", "BAKERY", "CONTRACTING", "SERVICES", "INTERNATIONAL", "STATIONERY", "FURNITURE", "JEWELLERY", "BOUTIQUE", "PETROLEUM", "STATION", "CENTER", "CENTRE", "MARKET", "COFFEE", "ROASTERY", "KITCHEN", "CAFE", "STORE", "SHOP"].filter {
            last.count >= 4 && last.count < $0.count && Double(last.count) / Double($0.count) >= 0.6 && $0.hasPrefix(last.uppercased())
        }
        guard candidates.count == 1, let completion = candidates.first else { return name }
        let replacement = last == last.uppercased() ? completion : last == last.lowercased() ? completion.lowercased() : completion
        return (words.dropLast() + [replacement]).joined(separator: " ")
    }

    public static func key(_ name: String) -> String {
        var value = clean(name).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        value = value.replacingOccurrences(of: #"(?i)(?:\s+(?:br|branch)\s*#?\s*\d+|\s+#\s*\d+)$"#, with: "", options: .regularExpression)
        for (from, to) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه")] { value = value.replacingOccurrences(of: from, with: to) }
        value = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        let suffixes: Set<String> = ["llc", "fze", "fzco", "est", "establishment", "trading", "co", "company", "cafeteria", "cafeter", "restaurant", "restauran", "br", "branch"]
        var words = value.split(separator: " ").map(String.init)
        while let last = words.last, suffixes.contains(last) || (last.hasPrefix("#") && last.dropFirst().allSatisfy(\.isNumber)) { words.removeLast() }
        return words.joined(separator: " ")
    }

    public static func displayName(_ raw: String?, aliases: [String: String]) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return aliases[key(raw)]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? clean(raw)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
