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
            .frame(minHeight: 56)
            .background(tint.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel(GhafCurrencyIcon.name(selection, languageCode: languageCode))
    }
}

/// An amount with its real currency sign (AED, SAR, OMR) or ISO code, masked with sparkles when hidden.
struct GhafMoneyLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let amount: Decimal
    let currency: String
    let languageCode: String
    var size: CGFloat = 17
    var weight: Font.Weight = .heavy
    var hidden = false
    /// The eye toggle on Home hides every amount in the app, not just Home's.
    @AppStorage(GhafFormat.hideBalancesKey) private var hiddenEverywhere = false

    private var isHidden: Bool { hidden || hiddenEverywhere }

    // Formatters are costly to build; reuse per language and currency precision (main thread only).
    private static let formatters: [String: [Int: NumberFormatter]] = ["ar": "ar_AE", "en": "en_AE"].mapValues { id in
        [2, 3].reduce(into: [:]) { result, digits in
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: id)
            formatter.minimumFractionDigits = digits
            formatter.maximumFractionDigits = digits
            result[digits] = formatter
        }
    }

    private var number: String {
        return Self.formatter(languageCode: languageCode, currency: currency).string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    static func formatter(languageCode: String, currency: String) -> NumberFormatter {
        formatters[languageCode == "ar" ? "ar" : "en"]![GhafCurrencyDigits.fractionDigits(for: currency)]!
    }

    @ViewBuilder private var numberText: some View {
        HStack(spacing: 0) {
            ForEach(Array(number.enumerated()), id: \.offset) { item in
                let character = item.element
                GhafMoneyGlyph(character: character, hidden: isHidden,
                               size: size, weight: weight,
                               reduceMotion: reduceMotion)
            }
        }
    }

    var body: some View {
        HStack(spacing: size * 0.22) {
            if GhafCurrencyIcon.assetName(currency) != nil {
                GhafCurrencyIcon(currency: currency, size: size * 0.82)
            } else {
                Text(currency.uppercased())
                    .font(GhafTypography.number(size * 0.55, weight: weight))
            }
            numberText
                .font(GhafTypography.number(size, weight: weight))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isHidden ? (languageCode == "ar" ? "المبلغ مخفي" : "Amount hidden")
                                   : "\(number) \(GhafCurrencyIcon.name(currency, languageCode: languageCode))")
    }
}

private struct GhafMoneyGlyph: View {
    let character: Character
    let hidden: Bool
    let size: CGFloat
    let weight: Font.Weight
    let reduceMotion: Bool

    /// Owner 1.31: the eye hide must read as a deliberate ~0.7 s ease-in-out, not a 0.2 s snap.
    static func hideAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.45, 0, 0.2, 1, duration: 0.7)
    }

    private var digitWidth: CGFloat { size * 0.60 }
    private var columnHeight: CGFloat { size * 1.25 }

    var body: some View {
        if character.isNumber {
            ZStack {
                Text(String(character))
                    .contentTransition(.numericText())
                    .offset(y: hidden && !reduceMotion ? -columnHeight : 0)
                    .opacity(hidden ? 0 : 1)
                Text("•")
                    .font(GhafTypography.number(size, weight: weight))
                    .frame(width: digitWidth)
                    .offset(y: !hidden && !reduceMotion ? columnHeight : 0)
                    .opacity(hidden ? 1 : 0)
            }
            .frame(width: digitWidth, height: columnHeight)
            .clipped()
            .animation(Self.hideAnimation(reduceMotion), value: hidden)
        } else {
            // Separators are the only flexible pieces in a tight row; fixedSize stops "100.00" being squeezed to "10000" (V2).
            Text(String(character))
                .fixedSize()
                .layoutPriority(1)
                .animation(Self.hideAnimation(reduceMotion), value: hidden)
        }
    }
}

/// Text with the currency mark in place of "AED", "SAR" or "OMR" next to an amount, sized to the
/// text, so sentences ("You spent AED 3,582.50") show the same mark as every other amount.
enum GhafMoneyText {
    /// Keeps embedded amounts in their own directional run inside Arabic sentences.
    static func isolate(_ amount: String) -> String { "\u{2068}\(amount)\u{2069}" }

    private static let codes = #"AED|SAR|OMR|د\.إ\.?|ر\.س\.?|ر\.ع\.?"#
    private static let pattern = try! NSRegularExpression(
        pattern: #"(\#(codes))[\s\x{200F}\x{00A0}]?(?=[0-9٠-٩])|(?<=[0-9٠-٩])[\s\x{200F}\x{00A0}]?(\#(codes))"#)
    private static func code(_ text: String) -> String {
        if text.hasPrefix("د") { return "AED" }
        if text.hasPrefix("ر.س") { return "SAR" }
        if text.hasPrefix("ر.ع") { return "OMR" }
        return text
    }
    private static var cache: [String: UIImage] = [:]

    static func text(_ string: String, size: CGFloat) -> Text {
        let ns = string as NSString
        var result = Text("")
        var cursor = 0
        for match in pattern.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            let codeRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard let mark = image(for: code(ns.substring(with: codeRange)), size: size) else { continue }
            result = result + Text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            // A thin space keeps the mark off the digits on either side.
            result = result + Text(Image(uiImage: mark)).baselineOffset(-size * 0.08) + Text("\u{2009}")
            cursor = match.range.location + match.range.length
        }
        return result + Text(ns.substring(from: cursor))
    }

    /// The asset redrawn at the text's cap height, as a template so it takes the text colour.
    private static func image(for code: String, size: CGFloat) -> UIImage? {
        let key = "\(code)-\(size)"
        if let cached = cache[key] { return cached }
        guard let name = GhafCurrencyIcon.assetName(code), let source = UIImage(named: name) else { return nil }
        let height = size * 0.78
        let width = height * source.size.width / max(source.size.height, 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }.withRenderingMode(.alwaysTemplate)
        cache[key] = image
        return image
    }
}
