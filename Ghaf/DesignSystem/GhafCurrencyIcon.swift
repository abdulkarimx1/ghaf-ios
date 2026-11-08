import SwiftUI

/// A compact currency mark, not a country flag.
/// GCC marks use the locally recognised currency abbreviation/symbol in a
/// dedicated coin-style badge so the visual remains distinct from ISO codes.
struct GhafCurrencyIcon: View {
    let currency: String
    var size: CGFloat = 24

    private var normalized: String { currency.uppercased() }

    private var mark: String {
        switch normalized {
        case "AED": "د.إ"
        case "SAR": "ر.س"
        case "OMR": "ر.ع"
        case "QAR": "ر.ق"
        case "KWD": "د.ك"
        case "BHD": "د.ب"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        default: "¤"
        }
    }

    private var tint: Color {
        switch normalized {
        case "AED": Color(red: 0.10, green: 0.43, blue: 0.30)
        case "SAR": Color(red: 0.12, green: 0.43, blue: 0.34)
        case "OMR": Color(red: 0.60, green: 0.20, blue: 0.18)
        case "QAR": Color(red: 0.43, green: 0.15, blue: 0.29)
        case "KWD": Color(red: 0.18, green: 0.30, blue: 0.48)
        case "BHD": Color(red: 0.60, green: 0.19, blue: 0.25)
        case "USD": Color(red: 0.18, green: 0.34, blue: 0.52)
        case "EUR": Color(red: 0.22, green: 0.31, blue: 0.62)
        case "GBP": Color(red: 0.42, green: 0.22, blue: 0.43)
        default: .secondary
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Circle()
                .stroke(tint.opacity(0.42), lineWidth: max(0.8, size * 0.045))
                .padding(size * 0.055)
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: max(0.6, size * 0.025))
                .padding(size * 0.17)

            Text(mark)
                .font(markFont)
                .foregroundStyle(tint)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .padding(size * 0.17)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isImage)
    }

    private var markFont: Font {
        switch normalized {
        case "AED", "SAR", "OMR", "QAR", "KWD", "BHD":
            .system(size: size * 0.36, weight: .bold, design: .rounded)
        default:
            .system(size: size * 0.57, weight: .bold, design: .rounded)
        }
    }

    private var accessibilityName: String {
        switch normalized {
        case "AED": "UAE dirham"
        case "SAR": "Saudi riyal"
        case "KWD": "Kuwaiti dinar"
        case "BHD": "Bahraini dinar"
        case "OMR": "Omani rial"
        case "QAR": "Qatari riyal"
        case "USD": "US dollar"
        case "EUR": "Euro"
        case "GBP": "British pound"
        default: "(normalized) currency"
        }
    }
}
