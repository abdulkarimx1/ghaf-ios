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
    /// Opens the pad as soon as the field appears (quick add).
    var presentOnAppear = false

    @State private var presented = false
    @State private var keyPress = 0
    @State private var replaceOnNextKey = true
    @Environment(\.locale) private var locale

    private var digits: Int { integerMode ? 0 : currency.map(GhafCurrencyDigits.fractionDigits(for:)) ?? 2 }
    private var separator: String { (languageCode == "ar" ? Locale(identifier: "ar_AE") : locale).decimalSeparator ?? "." }

    var body: some View {
        Button { openPad() } label: {
            VStack(spacing: 4) {
                if !label.isEmpty {
                    Text(label).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.secondaryText)
                }
                HStack(spacing: 8) {
                    if let currency { GhafCurrencyIcon(currency: currency, size: fontSize * 0.82).foregroundStyle(theme.primaryText) }
                    Text(value.isEmpty ? placeholder : localized(value))
                        .font(GhafTypography.number(fontSize, weight: .bold))
                        .foregroundStyle(value.isEmpty ? theme.secondaryText : theme.primaryText)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: label.isEmpty ? max(56, fontSize + 32) : max(64, fontSize + 40))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: theme.surface)
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

    private var placeholder: String { localized("0" + (digits > 0 ? "." + String(repeating: "0", count: digits) : "")) }

    private var keypad: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 48, height: 44).accessibilityHidden(true)
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text(label).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    HStack(spacing: 8) {
                        if let currency { GhafCurrencyIcon(currency: currency, size: 20) }
                        Text(value.isEmpty ? placeholder : localized(value))
                            .font(GhafTypography.number(30, weight: .bold))
                            .foregroundStyle(value.isEmpty ? theme.secondaryText : theme.primaryText)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
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
                            .background(theme.name == "Graphite" ? theme.surface.opacity(0.72) : theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
        .background(.ultraThinMaterial)
        .background(theme.background.opacity(0.86))
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    private func openPad() { replaceOnNextKey = true; presented = true }

    private func press(_ key: String) {
        if replaceOnNextKey {
            replaceOnNextKey = false
            if key == "delete" { value = ""; keyPress += 1; return }
            value = ""
        }
        if key == "delete" {
            if !value.isEmpty { value.removeLast() }
        } else if key == separator {
            guard digits > 0, !value.contains(".") else { return }
            value = value.isEmpty ? "0." : value + "."
        } else {
            let fraction = value.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
            let integral = value.split(separator: ".", omittingEmptySubsequences: false).first?.count ?? 0
            guard fraction < digits || !value.contains("."), value.contains(".") || integral < maxDigits else { return }
            value += key
        }
        keyPress += 1
    }

    private func localized(_ text: String) -> String {
        guard languageCode == "ar" else { return text.replacingOccurrences(of: ".", with: separator) }
        return text.replacingOccurrences(of: ".", with: separator).map { char in
            guard let digit = char.wholeNumberValue, (0...9).contains(digit) else { return char }
            return Character(UnicodeScalar(0x0660 + digit)!)
        }.map(String.init).joined()
    }
}
