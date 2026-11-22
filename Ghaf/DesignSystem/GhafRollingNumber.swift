import SwiftUI

/// A money value that uses SwiftUI's numeric odometer transition when its amount changes.
/// Currency artwork and separators remain fixed as the digits roll.
struct GhafRollingNumber: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let amount: Decimal
    let currency: String
    let languageCode: String
    var size: CGFloat = 40
    var weight: Font.Weight = .heavy
    var hidden = false

    var body: some View {
        GhafMoneyLabel(amount: amount, currency: currency, languageCode: languageCode, size: size, weight: weight, hidden: hidden)
            .contentTransition(.numericText(value: NSDecimalNumber(decimal: amount).doubleValue))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0), value: amount)
    }
}
