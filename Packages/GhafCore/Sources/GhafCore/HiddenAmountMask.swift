import Foundation

/// Masks every numeric digit while retaining decimal and grouping separators.
public enum HiddenAmountMask {
    public static func string(from formattedNumber: String) -> String {
        String(formattedNumber.map { $0.isNumber ? "•" : $0 })
    }
}
