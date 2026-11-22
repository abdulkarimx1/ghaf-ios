import Foundation

/// Masks only whole-number digits while retaining grouping separators for a stable, readable shape.
public enum HiddenAmountMask {
    public static func string(from formattedNumber: String) -> String {
        let decimalIndex: String.Index? = {
            if let index = formattedNumber.lastIndex(where: { $0 == "." || $0 == "٫" }) { return index }
            guard let comma = formattedNumber.lastIndex(of: ",") else { return nil }
            let fraction = formattedNumber[formattedNumber.index(after: comma)...]
            return !fraction.isEmpty && fraction.count <= 2 && fraction.allSatisfy(\.isNumber) ? comma : nil
        }()
        let integer = decimalIndex.map { formattedNumber[..<$0] } ?? formattedNumber[...]
        return String(integer.map { $0.isNumber ? "★" : $0 })
    }
}
