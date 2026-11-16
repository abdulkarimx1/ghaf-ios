import Foundation

/// Turns written replies into what a person would say: "AED 4.00" becomes "4 dirhams", "4.50 AED"
/// "4 dirhams 50 fils", and symbols a voice would read out ("·", "→", "•") become pauses.
public enum SpokenMoney {
    private static let amount = #"([0-9٠-٩][0-9٠-٩,٬]*(?:[.٫][0-9٠-٩]{1,2})?)"#
    private static let codes = #"(?:AED|Dhs?|DHS?|dhs?|د\.إ\.?|درهم|دراهم|درهماً)"#
    private static let before = try! NSRegularExpression(pattern: codes + #"[\s\x{00A0}\x{200F}]*"# + amount)
    private static let after = try! NSRegularExpression(pattern: amount + #"[\s\x{00A0}\x{200F}]*"# + codes)

    public static func speakable(_ text: String, arabic: Bool) -> String {
        var result = text
        for regex in [before, after] {
            let ns = result as NSString
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                let raw = ns.substring(with: match.range(at: 1))
                result = (result as NSString).replacingCharacters(in: match.range, with: words(raw, arabic: arabic))
            }
        }
        for (symbol, pause) in [("·", ","), ("→", arabic ? "،" : ","), ("←", "،"), ("•", ""), ("*", ""), ("#", "")] {
            result = result.replacingOccurrences(of: symbol, with: pause)
        }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// "4.50" → "4 dirhams 50 fils"; Arabic follows its number agreement (درهم، درهمين، دراهم، درهماً).
    static func words(_ raw: String, arabic: Bool) -> String {
        let western = GhafVoiceTransactionParser.normalizeNumerals(raw)
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "٬", with: "").replacingOccurrences(of: "٫", with: ".")
        let value = Decimal(string: western, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        var whole = Decimal(), copy = value
        NSDecimalRound(&whole, &copy, 0, .down)
        let fils = NSDecimalNumber(decimal: (value - whole) * 100).intValue
        let n = NSDecimalNumber(decimal: whole).intValue
        let number = NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
        if arabic {
            let unit = n == 1 ? "درهم واحد" : n == 2 ? "درهمين" : (3...10).contains(n % 100) ? "\(number) دراهم" : "\(number) درهم"
            return fils > 0 ? "\(unit) و\(fils) فلس" : unit
        }
        let unit = n == 1 ? "1 dirham" : "\(number) dirhams"
        return fils > 0 ? "\(unit) \(fils) fils" : unit
    }
}

/// Spoken or typed edits to the entries Ghaf just drafted: "yes", "cancel", "remove the coffee",
/// "rename karak to tea", and their Arabic forms. Amount changes stay with `ChatCorrection`.
public enum ChatEdit: Equatable {
    case confirm
    case cancel
    /// Index into the recent names passed in (0 = most recent).
    case remove(Int)
    case rename(Int, String)

    private static let yes: Set<String> = ["yes", "yeah", "yep", "ok", "okay", "sure", "save", "save it", "save them", "yes save",
                                           "yes please", "go ahead", "do it", "correct", "نعم", "ايوه", "ايه", "اي", "اوكي", "تمام",
                                           "احفظ", "احفظها", "احفظهم", "زين", "صح", "اكيد", "يب", "اوك"]
    private static let no: Set<String> = ["no", "nope", "cancel", "never mind", "nevermind", "discard", "forget it", "dont save",
                                          "لا", "الغ", "الغي", "الغاء", "خلاص لا", "لا تحفظ", "انس", "انسى", "مو لازم"]
    private static let removeCues = ["remove", "delete", "drop", "take out", "take off", "without", "شيل", "احذف", "امسح", "بدون", "حذف"]
    private static let renameCues = ["rename", "call", "name", "سم", "سمي", "غير اسم", "اسمه", "اسمها"]

    public static func parse(_ text: String, recent: [String]) -> ChatEdit? {
        let key = CategoryMatcher.normalize(text).trimmingCharacters(in: .whitespaces)
        if yes.contains(key) { return .confirm }
        if no.contains(key) { return .cancel }
        let padded = " \(key) "

        if let cue = removeCues.first(where: { padded.contains(" \($0) ") }) {
            let rest = key.components(separatedBy: cue).last ?? ""
            if ["last", "الاخير", "الاخيره"].contains(where: { rest.contains($0) }) { return recent.isEmpty ? nil : .remove(0) }
            if let index = match(rest, in: recent) { return .remove(index) }
            return nil
        }
        if let cue = renameCues.first(where: { padded.contains(" \($0) ") }) {
            // "<cue> OLD to NEW" / "<cue> OLD الى NEW"
            let rest = key.components(separatedBy: cue).dropFirst().joined(separator: cue).trimmingCharacters(in: .whitespaces)
            for separator in [" to ", " as ", " الى ", " إلى "] {
                let parts = rest.components(separatedBy: separator)
                guard parts.count == 2, let index = match(parts[0], in: recent) else { continue }
                let name = parts[1].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return .rename(index, name) }
            }
        }
        return nil
    }

    /// The recent entry whose name the words mention.
    private static func match(_ words: String, in recent: [String]) -> Int? {
        let said = CategoryMatcher.normalize(words).split(separator: " ").map { strip(String($0)) }
        return recent.firstIndex { name in
            let parts = CategoryMatcher.normalize(name).split(separator: " ").map { strip(String($0)) }.filter { $0.count >= 3 }
            return !parts.isEmpty && parts.contains(where: said.contains)
        }
    }

    private static func strip(_ word: String) -> String {
        word.hasPrefix("ال") && word.count > 4 ? String(word.dropFirst(2)) : word
    }
}
