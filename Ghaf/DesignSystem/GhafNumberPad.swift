import SwiftUI

struct GhafAmountField: View {
    @Binding var value: String
    let currency: String?
    let label: String
    let theme: GhafTheme
    let languageCode: String
    var integerMode = false
    /// Longest number allowed, e.g. 4 for a card's last four digits.
    var maxDigits = 12
    var fontSize: CGFloat = 24
    var chromeless = false
    var trailingAligned = false
    var groupsDigits = false
    /// Opens the pad as soon as the field appears (quick add).
    var presentOnAppear = false

    @State private var presented = false
    @State private var keyPress = 0
    @State private var replaceOnNextKey = true

    private var digits: Int { integerMode ? 0 : currency.map(GhafCurrencyDigits.fractionDigits(for:)) ?? 2 }
    var body: some View {
        Button { openPad() } label: {
            Group {
              if chromeless {
                amountContent
                    .frame(maxWidth: .infinity, minHeight: label.isEmpty ? max(56, fontSize + 32) : max(64, fontSize + 40))
              } else {
                amountContent
                    .frame(maxWidth: .infinity, minHeight: label.isEmpty ? max(56, fontSize + 32) : max(64, fontSize + 40))
                    .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value.isEmpty ? placeholder : localized(value))
        .accessibilityHint(languageCode == "ar" ? "يفتح لوحة إدخال الأرقام" : "Opens the number pad")
        .sheet(isPresented: $presented) {
            keypad
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: keyPress)
        .onAppear { if presentOnAppear { openPad() } }
        .onChange(of: presented) { _, isPresented in if isPresented { replaceOnNextKey = true } }
    }

    private var amountContent: some View {
            VStack(spacing: 4) {
                if !label.isEmpty {
                    Text(label).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.secondaryText)
                }
                HStack(spacing: 8) {
                    if let currency { GhafCurrencyIcon(currency: currency, size: fontSize * 0.82).foregroundStyle(theme.primaryText) }
                    let display = amountDisplay(value.isEmpty ? placeholder : paddedAmount(value))
                    Group {
                        if languageCode == "ar" {
                            Text(display)
                        } else { Text(display) }
                    }
                    .font(languageCode == "ar"
                          ? GhafTypography.body(fontSize, languageCode: languageCode, weight: .bold)
                          : GhafTypography.number(fontSize, weight: .bold))
                    .foregroundStyle(value.isEmpty ? theme.secondaryText : theme.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: trailingAligned ? .trailing : .center)
                .multilineTextAlignment(trailingAligned ? .trailing : .center)
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, chromeless ? 0 : 16)
            .environment(\.layoutDirection, .leftToRight)
    }

    private var placeholder: String { localized("0" + (digits > 0 ? "." + String(repeating: "0", count: digits) : "")) }

    private func paddedAmount(_ value: String) -> String {
        guard digits > 0, !integerMode else { return value }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return String(parts[0]) + "." + fraction + String(repeating: "0", count: max(0, digits - fraction.count))
    }

    private var keypad: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 48, height: 44).accessibilityHidden(true)
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text(label).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    HStack(spacing: 8) {
                        if let currency { GhafCurrencyIcon(currency: currency, size: 20) }
                        Text(amountDisplay(value.isEmpty ? placeholder : value))
                            .font(languageCode == "ar"
                                  ? GhafTypography.body(fontSize, languageCode: languageCode, weight: .bold)
                                  : GhafTypography.number(fontSize, weight: .bold))
                            .foregroundStyle(value.isEmpty ? theme.secondaryText : theme.primaryText)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .combine)
                Spacer()
                Button { presented = false } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(width: 48, height: 44)
                        .background(theme.accent, in: Capsule())
                }
                .accessibilityLabel(languageCode == "ar" ? "تم" : "Done")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", digits > 0 ? separator : "", "0", "delete"], id: \.self) { key in
                    if key.isEmpty {
                        Color.clear.frame(height: 64)
                    } else {
                        Button { press(key) } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left") }
                                else { Text(localized(key)) }
                            }
                            .font(GhafTypography.number(23, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background {
                                let keyShape = RoundedRectangle(cornerRadius: 15, style: .continuous)
                                keyShape.fill(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "delete" ? (languageCode == "ar" ? "حذف" : "Delete") : localized(key))
                        .onLongPressGesture { if key == "delete" { value = ""; keyPress += 1 } }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    private func openPad() {
        #if DEBUG
        assert(Self.applying("7", to: "125.50", replace: true, digits: 2, maxDigits: 12, separator: ",") == "7")
        assert(Self.applying("delete", to: "125.50", replace: true, digits: 2, maxDigits: 12, separator: ".").isEmpty)
        #endif
        replaceOnNextKey = true
        presented = true
    }

    static func applying(_ key: String, to current: String, replace: Bool, digits: Int, maxDigits: Int, separator: String) -> String {
        var value = replace ? "" : current
        if key == "delete" { if !replace && !value.isEmpty { value.removeLast() }; return value }
        if key == separator {
            guard digits > 0, !value.contains(".") else { return value }
            return value.isEmpty ? "0." : value + "."
        }
        let fraction = value.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        let integral = value.split(separator: ".", omittingEmptySubsequences: false).first?.count ?? 0
        guard fraction < digits || !value.contains("."), value.contains(".") || integral < maxDigits else { return value }
        value += key
        return value
    }

    private func press(_ key: String) {
        value = Self.applying(key, to: value, replace: replaceOnNextKey, digits: digits, maxDigits: maxDigits, separator: separator)
        replaceOnNextKey = false
        keyPress += 1
    }

    private func localized(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: separator)
    }

    private func amountDisplay(_ text: String) -> String {
        let display: String
        if groupsDigits, let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: languageCode == "ar" ? "ar_AE" : "en_AE")
            formatter.usesGroupingSeparator = true
            formatter.minimumFractionDigits = digits
            formatter.maximumFractionDigits = digits
            display = formatter.string(from: amount as NSDecimalNumber) ?? localized(text)
        } else {
            display = localized(text)
        }
        return languageCode == "ar" ? "\u{2066}\(display)\u{2069}" : display
    }
}
