import Foundation

enum GhafCompactNumber {
    static func string(_ value: Double, languageCode: String) -> String {
        let locale = GhafLocale.locale(identifier: languageCode)
        let magnitude = abs(value)
        let (scaled, suffix): (Double, String) = magnitude >= 1_000_000 ? (value / 1_000_000, "M")
            : magnitude >= 1_000 ? (value / 1_000, "K") : (value, "")
        let decimals = suffix.isEmpty || scaled.rounded() == scaled ? 0 : 1
        return scaled.formatted(.number.precision(.fractionLength(decimals)).locale(locale)) + suffix
    }
}
