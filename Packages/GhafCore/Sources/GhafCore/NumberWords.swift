import Foundation

/// Turns spoken amounts into digits: "one hundred and twenty" → "120", "خمسة وعشرين" → "25",
/// "مية وخمسين" → "150", "خمسة ونص" → "5.5". Covers English and Gulf/Modern Standard Arabic.
/// When the text already has digits, a lone small word ("one coffee 15") is left alone.
public enum NumberWords {

    public static func replace(in text: String) -> String {
        let hasDigits = text.rangeOfCharacter(from: .decimalDigits) != nil
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            guard let (value, used) = readNumber(tokens, from: index), !(hasDigits && used == 1 && value < 10) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            output.append(format(value))
            index += used
        }
        return output.joined(separator: " ")
    }

    /// Reads the longest run of number words starting at `start`.
    private static func readNumber(_ tokens: [String], from start: Int) -> (Decimal, Int)? {
        var total: Decimal = 0
        var current: Decimal = 0
        var index = start
        var consumed = 0
        var sawNumber = false

        while index < tokens.count {
            var word = clean(tokens[index])
            // Arabic "و" (and) / "ب" (for) glued to a number: "وعشرين", "بخمسة".
            if word.count > 1, word.hasPrefix("و") || word.hasPrefix("ب"), lookup(String(word.dropFirst())) != nil {
                if word.hasPrefix("و") && !sawNumber { break }
                word = String(word.dropFirst())
            }

            if let value = units[word] ?? tens[word] {
                current += value
            } else if let value = fractions[word], sawNumber {
                current += value
            } else if let value = hundreds[word] {
                current = (current == 0 ? 1 : current) * 100 * value
            } else if word == "hundred" {
                current = (current == 0 ? 1 : current) * 100
            } else if let value = thousands[word] {
                total += (current == 0 ? 1 : current) * value
                current = 0
            } else if (word == "and" || word == "و"), sawNumber, index + 1 < tokens.count,
                      lookup(clean(tokens[index + 1])) != nil {
                index += 1
                consumed += 1
                continue
            } else if word == "a", !sawNumber, index + 1 < tokens.count,
                      ["hundred", "thousand"].contains(clean(tokens[index + 1])) {
                current = 1
                index += 1
                consumed += 1
                continue
            } else {
                break
            }
            sawNumber = true
            index += 1
            consumed += 1
        }
        guard sawNumber else { return nil }
        return (total + current, consumed)
    }

    private static func lookup(_ word: String) -> Decimal? {
        units[word] ?? tens[word] ?? hundreds[word] ?? thousands[word] ?? fractions[word] ?? (word == "hundred" ? 100 : nil)
    }

    private static func clean(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
    }

    private static func format(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    // Arabic keys are pre-normalised the same way `clean` does (أ/إ → ا, ة → ه, ى → ي).
    private static let units: [String: Decimal] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "واحد": 1, "وحده": 1, "اثنين": 2, "اثنان": 2, "ثنين": 2, "ثلاث": 3, "ثلاثه": 3, "اربع": 4, "اربعه": 4,
        "خمس": 5, "خمسه": 5, "ست": 6, "سته": 6, "سبع": 7, "سبعه": 7, "ثمان": 8, "ثمانيه": 8, "ثمنيه": 8, "ثمن": 8,
        "تسع": 9, "تسعه": 9, "عشر": 10, "عشره": 10,
        "احدعش": 11, "احدعشر": 11, "اثنعش": 12, "اثناعشر": 12, "ثلطعش": 13, "ثلاثطعش": 13, "ثلاثعشر": 13,
        "اربعطعش": 14, "اربعتعش": 14, "خمسطعش": 15, "خمستعش": 15, "خمسعشر": 15, "ستطعش": 16, "ستعش": 16,
        "سبعطعش": 17, "سبعتعش": 17, "ثمنطعش": 18, "ثمنتعش": 18, "تسعطعش": 19, "تسعتعش": 19
    ]
    private static let tens: [String: Decimal] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "عشرين": 20, "ثلاثين": 30, "اربعين": 40, "خمسين": 50, "ستين": 60, "سبعين": 70, "ثمانين": 80, "تسعين": 90
    ]
    /// Arabic hundreds come as one word ("ميتين", "ثلاثمية"); the value is the multiplier of 100.
    private static let hundreds: [String: Decimal] = [
        "ميه": 1, "مئه": 1, "مائه": 1, "مية": 1, "ميتين": 2, "مئتين": 2, "مائتين": 2, "ثلاثميه": 3, "ثلاثمائه": 3,
        "اربعميه": 4, "اربعمائه": 4, "خمسميه": 5, "خمسمائه": 5, "ستميه": 6, "ستمائه": 6, "سبعميه": 7, "سبعمائه": 7,
        "ثمانميه": 8, "ثمنميه": 8, "ثمانمائه": 8, "تسعميه": 9, "تسعمائه": 9
    ]
    private static let thousands: [String: Decimal] = [
        "thousand": 1000, "الف": 1000, "الفين": 2000, "الاف": 1000, "آلاف": 1000
    ]
    private static let fractions: [String: Decimal] = [
        "half": 0.5, "نص": 0.5, "نصف": 0.5, "ربع": 0.25
    ]
}
