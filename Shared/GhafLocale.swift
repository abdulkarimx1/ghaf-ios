import Foundation

enum GhafLocale {
    static func locale(identifier: String) -> Locale {
        guard identifier.lowercased().hasPrefix("ar"), !identifier.lowercased().contains("numbers=") else {
            return Locale(identifier: identifier)
        }
        return Locale(identifier: identifier + "@numbers=latn")
    }
}
