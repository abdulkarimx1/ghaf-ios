import Foundation

enum GhafLocale {
    static func locale(identifier: String) -> Locale {
        guard identifier.lowercased().hasPrefix("ar"), !identifier.lowercased().contains("numbers=") else {
            return Locale(identifier: identifier)
        }
        return Locale(identifier: identifier + "@numbers=latn")
    }

    static func decimalString(_ value: Decimal, identifier: String, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale(identifier: identifier)
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
