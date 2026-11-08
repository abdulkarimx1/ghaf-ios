import SwiftUI

/// Currency pictograms: intentionally not country flags or ISO-code badges.
struct GhafCurrencyIcon: View {
    let currency: String
    var size: CGFloat = 24

    private var normalized: String { currency.uppercased() }

    private var symbol: String {
        switch normalized {
        case "AED": "banknote.fill"
        case "SAR": "banknote"
        case "OMR": "building.columns.fill"
        case "QAR": "diamond.fill"
        case "KWD": "circle.hexagongrid.fill"
        case "BHD": "seal.fill"
        case "USD": "dollarsign.circle.fill"
        case "EUR": "eurosign.circle.fill"
        case "GBP": "sterlingsign.circle.fill"
        default: "circle.dotted"
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
            Circle().fill(tint.opacity(0.12))
            Circle()
                .stroke(tint.opacity(0.34), lineWidth: max(0.8, size * 0.045))
                .padding(size * 0.055)
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.49, weight: .semibold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isImage)
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
        default: "\(normalized) currency"
        }
    }
}
