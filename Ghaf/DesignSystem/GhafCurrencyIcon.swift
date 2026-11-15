import SwiftUI

/// Currency mark: the official sign for AED, SAR and OMR, the ISO code as text for everything else.
struct GhafCurrencyIcon: View {
    let currency: String
    var size: CGFloat = 24

    private var code: String { currency.uppercased() }

    var body: some View {
        Group {
            if let asset = Self.assetName(code) {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Text(code)
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: size, minHeight: size)
            }
        }
        .accessibilityLabel(Self.name(code, languageCode: "en"))
    }

    static func assetName(_ code: String) -> String? {
        switch code.uppercased() {
        case "AED": "CurrencyAED"
        case "SAR": "CurrencySAR"
        case "OMR": "CurrencyOMR"
        default: nil
        }
    }

    static func name(_ code: String, languageCode: String) -> String {
        let ar = languageCode == "ar"
        switch code.uppercased() {
        case "AED": return ar ? "درهم إماراتي" : "UAE dirham"
        case "SAR": return ar ? "ريال سعودي" : "Saudi riyal"
        case "KWD": return ar ? "دينار كويتي" : "Kuwaiti dinar"
        case "BHD": return ar ? "دينار بحريني" : "Bahraini dinar"
        case "OMR": return ar ? "ريال عماني" : "Omani rial"
        case "QAR": return ar ? "ريال قطري" : "Qatari riyal"
        case "USD": return ar ? "دولار أمريكي" : "US dollar"
        case "EUR": return ar ? "يورو" : "Euro"
        case "GBP": return ar ? "جنيه إسترليني" : "British pound"
        default: return code.uppercased()
        }
    }
}

/// Menu-style currency selector that keeps its size when the choice changes.
struct GhafCurrencyPicker: View {
    @Binding var selection: String
    let currencies: [String]
    let languageCode: String
    var tint: Color = .accentColor

    var body: some View {
        Menu {
            ForEach(currencies, id: \.self) { code in
                Button {
                    selection = code
                } label: {
                    if let asset = GhafCurrencyIcon.assetName(code) {
                        Label { Text("\(code) · \(GhafCurrencyIcon.name(code, languageCode: languageCode))") } icon: { Image(asset).renderingMode(.template) }
                    } else {
                        Text("\(code) · \(GhafCurrencyIcon.name(code, languageCode: languageCode))")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                GhafCurrencyIcon(currency: selection, size: 18)
                Text(selection)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(tint)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel(GhafCurrencyIcon.name(selection, languageCode: languageCode))
    }
}

/// An amount with its real currency sign (AED, SAR, OMR) or ISO code, masked with sparkles when hidden.
struct GhafMoneyLabel: View {
    let amount: Decimal
    let currency: String
    let languageCode: String
    var size: CGFloat = 17
    var hidden = false

    static let mask = "✦✦✦✦"

    private var number: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: languageCode == "ar" ? "ar_AE" : "en_AE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    var body: some View {
        HStack(spacing: size * 0.22) {
            if GhafCurrencyIcon.assetName(currency) != nil {
                GhafCurrencyIcon(currency: currency, size: size * 0.82)
            } else {
                Text(currency.uppercased())
                    .font(GhafTypography.number(size * 0.55, weight: .heavy))
            }
            Text(hidden ? Self.mask : number)
                .font(GhafTypography.number(hidden ? size * 0.7 : size, weight: .heavy))
                .tracking(hidden ? size * 0.08 : 0)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? (languageCode == "ar" ? "المبلغ مخفي" : "Amount hidden")
                                   : "\(number) \(GhafCurrencyIcon.name(currency, languageCode: languageCode))")
    }
}
