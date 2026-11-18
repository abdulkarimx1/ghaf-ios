import Foundation

public enum GroundedNumbers {
    public static func unsupported(in reply: String, sources: [String]) -> [Decimal] {
        let supported = sources.flatMap(numbers(in:))
        var seen = Set<Decimal>()
        return numbers(in: reply).filter { value in
            guard !supported.contains(where: { supports(value, source: $0) }) else { return false }
            return seen.insert(value).inserted
        }
    }

    private static func supports(_ value: Decimal, source: Decimal) -> Bool {
        if value == source { return true }
        var rounded = Decimal.zero
        var sourceValue = source
        NSDecimalRound(&rounded, &sourceValue, 0, .plain)
        return value == rounded
    }

    private static func numbers(in text: String) -> [Decimal] {
        let digits = String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if let digit = scalar.properties.numericValue, digit >= 0, digit <= 9, digit.rounded(.down) == digit,
               let ascii = UnicodeScalar(Int(digit) + 48) { return ascii }
            return scalar
        }))
        let pattern = #"(?<![\p{L}\p{N}])[0-9]+(?:[ ,٬][0-9]{3})*(?:[.٫][0-9]+)?(?![\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(digits.startIndex..., in: digits)
        return regex.matches(in: digits, range: range).compactMap { match in
            guard let range = Range(match.range, in: digits) else { return nil }
            let token = digits[range]
            let hasFraction = token.contains(".") || token.contains("٫")
            let normalized = token.replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "٬", with: "").replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "٫", with: ".")
            guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            if !hasFraction, value <= 31 || !hasFraction && value >= 1900 && value <= 2100 { return nil }
            return value
        }
    }
}
