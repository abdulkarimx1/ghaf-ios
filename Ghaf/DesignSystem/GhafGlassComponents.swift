import SwiftUI

extension View {
    /// White rounded card with a soft shadow (hairline outline instead in dark mode).
    func ghafCard(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(theme.surface).shadow(color: theme.shadow, radius: 14, x: 0, y: 6))
            .overlay { if theme.isDark { shape.stroke(theme.outline, lineWidth: 1) } }
    }

    func ghafBackground(theme: GhafTheme) -> some View {
        background(theme.background.ignoresSafeArea())
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
    /// When set, shows this card face (asset name) instead of `icon`.
    var cardAsset: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let cardAsset {
                Image(cardAsset).resizable().aspectRatio(1.6, contentMode: .fill)
                    .frame(width: 46, height: 29)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityHidden(true)
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

    private static func color(named name: String?) -> Color? {
        switch name?.lowercased() {
        case "orange": Color(red: 0.95, green: 0.50, blue: 0.20)
        case "green": Color(red: 0.20, green: 0.66, blue: 0.42)
        case "blue": Color(red: 0.25, green: 0.52, blue: 0.95)
        case "red": Color(red: 0.92, green: 0.30, blue: 0.40)
        case "yellow": Color(red: 0.96, green: 0.72, blue: 0.10)
        case "teal": Color(red: 0.15, green: 0.70, blue: 0.80)
        case "purple": Color(red: 0.55, green: 0.40, blue: 0.95)
        case "pink": Color(red: 0.85, green: 0.36, blue: 0.66)
        case "gray", "grey": Color(red: 0.45, green: 0.52, blue: 0.60)
        default: nil
        }
    }

    private var style: (symbol: String, color: Color) {
        switch category {
        case "Groceries": ("basket.fill", Color(red: 0.20, green: 0.66, blue: 0.42))
        case "Dining": ("fork.knife", Color(red: 0.95, green: 0.50, blue: 0.20))
        case "Transport": ("car.fill", Color(red: 0.25, green: 0.52, blue: 0.95))
        case "Fuel": ("fuelpump.fill", Color(red: 0.90, green: 0.33, blue: 0.30))
        case "Bills & Utilities": ("bolt.fill", Color(red: 0.96, green: 0.72, blue: 0.10))
        case "Shopping": ("bag.fill", Color(red: 0.85, green: 0.36, blue: 0.66))
        case "Health": ("cross.case.fill", Color(red: 0.92, green: 0.30, blue: 0.40))
        case "Entertainment": ("play.rectangle.fill", Color(red: 0.55, green: 0.40, blue: 0.95))
        case "Travel": ("airplane", Color(red: 0.15, green: 0.70, blue: 0.80))
        case "Salary": ("banknote.fill", Color(red: 0.20, green: 0.66, blue: 0.42))
        case "Transfers": ("arrow.left.arrow.right", Color(red: 0.45, green: 0.52, blue: 0.60))
        case "Subscriptions": ("repeat", Color(red: 0.55, green: 0.40, blue: 0.95))
        default: ("creditcard.fill", tint)
        }
    }

    var body: some View {
        let custom = meta[category]
        GhafIconBadge(symbol: custom?.icon ?? style.symbol,
                      tint: Self.color(named: custom?.color) ?? style.color)
    }
}
