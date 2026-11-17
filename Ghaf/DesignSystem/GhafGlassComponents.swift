import SwiftUI

extension View {
    /// White rounded card with a soft shadow (hairline outline instead in dark mode).
    func ghafCard(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(theme.surface).shadow(color: theme.shadow, radius: 14, x: 0, y: 6))
            .overlay { if theme.isDark { shape.stroke(theme.outline, lineWidth: 1) } }
    }

    func ghafBackground(theme: GhafTheme) -> some View {
        background(ZStack {
            theme.background
            GhafCityBackdrop(theme: theme)
        }.ignoresSafeArea())
    }

    func ghafLiquidGlass(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius) -> some View {
        ghafCard(theme: theme, radius: radius)
    }

    /// Full-width primary action: a bold accent capsule.
    func ghafProminentButton(theme: GhafTheme, languageCode: String = "en") -> some View {
        buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, prominent: true))
    }

    /// Full-width secondary action: a tonal capsule.
    func ghafGlassButton(theme: GhafTheme, languageCode: String = "en") -> some View {
        buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, prominent: false))
    }
}

struct GhafCapsuleButtonStyle: ButtonStyle {
    let theme: GhafTheme
    let languageCode: String
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GhafTypography.body(17, languageCode: languageCode, weight: .bold))
            .foregroundStyle(prominent ? theme.accentContrast : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 18)
            .background(prominent ? theme.accent : theme.elevatedSurface, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .sensoryFeedback(.impact(weight: prominent ? .medium : .light), trigger: configuration.isPressed) { _, pressed in pressed }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round pill action (icon + label), the row of big buttons under the balance.
struct GhafPillButton: View {
    let title: String
    let icon: String
    let theme: GhafTheme
    let languageCode: String
    var prominent = false
    var badge = 0
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .symbolEffect(.bounce, value: taps)
                Text(title)
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if badge > 0 {
                    Text("\(badge)")
                        .font(GhafTypography.number(12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).frame(minHeight: 20)
                        .background(theme.over, in: Capsule())
                }
            }
            .foregroundStyle(prominent ? theme.accentContrast : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 10)
            .background {
                if prominent {
                    Capsule().fill(theme.accent)
                } else {
                    Capsule().fill(theme.surface).shadow(color: theme.shadow, radius: 10, x: 0, y: 4)
                }
            }
            .overlay { if theme.isDark && !prominent { Capsule().stroke(theme.outline, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.ghafPress)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
    }
}

/// Section title with an optional trailing text action ("See all").
struct GhafSectionHeader: View {
    let title: String
    let theme: GhafTheme
    let languageCode: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(GhafTypography.heading(20, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.ghafPress)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Round tinted glyph used by list rows and category icons.
struct GhafIconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Clean list row: round icon, title + subtitle, trailing content, chevron optional.
struct GhafListRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    let theme: GhafTheme
    let languageCode: String
    var chevron = false
    /// When set, shows this company's mark (or its initial) instead of `icon`.
    var brandName: String? = nil
    /// When set, shows this card face instead of `icon`.
    var card: GhafCardFace? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let card {
                card.accessibilityHidden(true)
            } else if let brandName {
                GhafBrandBadge(name: brandName, fallbackTint: tint)
            } else {
                GhafIconBadge(symbol: icon, tint: tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(GhafTypography.body(13, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
            if chevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

extension GhafListRow where Trailing == EmptyView {
    init(icon: String, tint: Color, title: String, subtitle: String? = nil, theme: GhafTheme,
         languageCode: String, chevron: Bool = false) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, theme: theme,
                  languageCode: languageCode, chevron: chevron) { EmptyView() }
    }
}

struct GhafTreeMark: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Ellipse().fill(color)
                    .frame(width: side * 0.66, height: side * 0.27)
                    .offset(y: -side * 0.17)
                Circle().fill(color)
                    .frame(width: side * 0.39, height: side * 0.39)
                    .offset(x: -side * 0.20, y: -side * 0.19)
                Circle().fill(color)
                    .frame(width: side * 0.39, height: side * 0.39)
                    .offset(x: side * 0.20, y: -side * 0.19)
                RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                    .fill(color)
                    .frame(width: side * 0.105, height: side * 0.42)
                    .offset(y: side * 0.23)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("Ghaf tree")
    }
}

private struct GhafCategoryMetaKey: EnvironmentKey {
    static let defaultValue: [String: GhafCategoryMeta] = [:]
}

extension EnvironmentValues {
    /// The user's category icons and colours, injected once at the root.
    var ghafCategoryMeta: [String: GhafCategoryMeta] {
        get { self[GhafCategoryMetaKey.self] }
        set { self[GhafCategoryMetaKey.self] = newValue }
    }
}

struct GhafCategoryIcon: View {
    let category: String
    let tint: Color
    @Environment(\.ghafCategoryMeta) private var meta
    @Environment(\.colorScheme) private var colorScheme

    /// Earthy palette drawn from the UAE (saffron, palm, Gulf water, dates, henna), each with a
    /// lighter shade for dark mode so glyphs stay readable on dark cards.
    enum Palette: String {
        case saffron, palm, gulf, ember, date, rose, coral, henna, sea, mint, stone, lavender

        var pair: (light: UInt32, dark: UInt32) {
            switch self {
            case .saffron: (0xC4741F, 0xF2A65A)
            case .palm: (0x3E7B4C, 0x7FC48D)
            case .gulf: (0x2B68A0, 0x7EB4E8)
            case .ember: (0xB3452D, 0xF08A70)
            case .date: (0xA87A22, 0xE6BE66)
            case .rose: (0xB0517A, 0xEC94B8)
            case .coral: (0xC0434F, 0xF28A93)
            case .henna: (0x6A4CAE, 0xB49CF0)
            case .sea: (0x1D8382, 0x6FD0CC)
            case .mint: (0x2C8A5A, 0x75D3A2)
            case .stone: (0x6E737C, 0xB4B8C0)
            case .lavender: (0x7D58B2, 0xC4A9EE)
            }
        }
    }

    private func color(_ palette: Palette) -> Color {
        let hex = colorScheme == .dark ? palette.pair.dark : palette.pair.light
        return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Colours a user picked for a custom category, mapped onto the same palette.
    private func color(named name: String?) -> Color? {
        switch name?.lowercased() {
        case "orange": color(.saffron)
        case "green": color(.palm)
        case "blue": color(.gulf)
        case "red": color(.coral)
        case "yellow": color(.date)
        case "teal": color(.sea)
        case "purple": color(.henna)
        case "pink": color(.rose)
        case "gray", "grey": color(.stone)
        default: nil
        }
    }

    private var style: (symbol: String, color: Color) {
        switch category {
        case "Groceries": ("basket.fill", color(.palm))
        case "Dining": ("fork.knife", color(.saffron))
        case "Transport": ("car.fill", color(.gulf))
        case "Fuel": ("fuelpump.fill", color(.ember))
        case "Bills & Utilities": ("bolt.fill", color(.date))
        case "Shopping": ("bag.fill", color(.rose))
        case "Health": ("cross.case.fill", color(.coral))
        case "Entertainment": ("play.rectangle.fill", color(.henna))
        case "Travel": ("airplane", color(.sea))
        case "Salary": ("banknote.fill", color(.mint))
        case "Transfers": ("arrow.left.arrow.right", color(.stone))
        case "Subscriptions": ("repeat", color(.lavender))
        default: ("creditcard.fill", tint)
        }
    }

    var body: some View {
        let custom = meta[category]
        GhafIconBadge(symbol: custom?.icon ?? style.symbol,
                      tint: color(named: custom?.color) ?? style.color)
    }
}
