import SwiftUI
import GhafCore

extension View {
    func ghafScreenPadding() -> some View {
        padding(.horizontal, GhafMetrics.gutter)
    }

    /// White rounded card with a soft shadow (hairline outline instead in dark mode).
    func ghafCard(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius) -> some View {
        modifier(GhafGlassSurface(theme: theme, radius: radius))
    }

    func ghafBackground(theme: GhafTheme) -> some View {
        background(ZStack {
            theme.background
            GhafCityBackdrop(theme: theme)
            GhafGlassBackground(theme: theme)
        }.ignoresSafeArea())
    }

    func ghafLiquidGlass(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius) -> some View {
        ghafCard(theme: theme, radius: radius)
    }

    func ghafGlassHero(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius, fallback: Color? = nil) -> some View {
        modifier(GhafGlassSurface(theme: theme, radius: radius, fallback: fallback))
    }

    func ghafGlassShape<S: Shape>(theme: GhafTheme, shape: S, fallback: Color) -> some View {
        modifier(GhafGlassShapeSurface(shape: shape, fallback: fallback))
    }

    /// Full-width primary action.
    func ghafProminentButton(theme: GhafTheme, languageCode: String = "en") -> some View {
        buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .primary))
    }

    /// Full-width secondary action: a tonal capsule.
    func ghafGlassButton(theme: GhafTheme, languageCode: String = "en") -> some View {
        buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .secondary))
    }

    func ghafDestructiveButton(theme: GhafTheme, languageCode: String = "en") -> some View {
        buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .destructive))
    }
}

private struct GhafGlassShapeSurface<S: Shape>: ViewModifier {
    let shape: S
    let fallback: Color
    func body(content: Content) -> some View {
        content.background(shape.fill(fallback))
    }
}

private struct GhafGlassBackground: View {
    let theme: GhafTheme
    @Environment(\.ghafGlass) private var glass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if glass.enabled && !reduceTransparency {
            GeometryReader { proxy in
                ZStack {
                    if glass.ambientGlow {
                        GhafGlassGlowBlobs(size: proxy.size, theme: theme)
                    }
                    if glass.grain { Image(uiImage: GhafGlassGrain.image).resizable(resizingMode: .tile).opacity(0.04).blendMode(.overlay).allowsHitTesting(false) }
                }
            }
        }
    }
}

private struct GhafGlassGlowBlobs: View {
    let size: CGSize
    let theme: GhafTheme
    var body: some View {
        let colorTheme = theme.name != "Graphite"
        ZStack {
            Circle().fill(theme.accent.opacity(theme.isDark ? (colorTheme ? 0.11 : 0.22) : (colorTheme ? 0.07 : 0.14))).frame(width: size.width * 0.9).blur(radius: 100).position(x: size.width * 0.18, y: size.height * 0.2)
            Circle().fill(theme.glow.opacity(theme.isDark ? (colorTheme ? 0.08 : 0.16) : (colorTheme ? 0.05 : 0.1))).frame(width: size.width * 0.8).blur(radius: 110).position(x: size.width * 0.82, y: size.height * 0.64)
        }
    }
}

struct GhafCapsuleButtonStyle: ButtonStyle {
    enum Role: Equatable { case primary, secondary, destructive }
    let theme: GhafTheme
    let languageCode: String
    let role: Role
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let graphite = theme.name == "Graphite"
        let colors: (foreground: Color, fill: Color) = {
            switch role {
            case .primary: return (graphite ? theme.background : theme.accentContrast, graphite ? theme.primaryText : theme.accent)
            case .secondary: return (theme.primaryText, theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06))
            case .destructive: return (theme.over, theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06))
            }
        }()
        configuration.label
            .font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52) // owner pick 1.31: height 52, radius 26
            .background(colors.fill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .sensoryFeedback(.impact(weight: role == .primary ? .medium : .light), trigger: configuration.isPressed) { _, pressed in pressed }
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .bold))
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
            .frame(minHeight: 60)
            .padding(.horizontal, 16)
            .background {
                if prominent {
                    Capsule().fill(theme.accent)
                } else {
                    Capsule().fill(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06))
                }
            }
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
    @Environment(\.ghafGlass) private var glass

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
                    .padding(.horizontal, 18)
                    .frame(minHeight: GhafMetrics.compactButtonHeight)
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
    var theme: GhafTheme? = nil

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                Circle().fill(tint.opacity(0.14))
            }
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
                GhafIconBadge(symbol: icon, tint: tint, theme: theme)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(GhafTypography.userContent(title, size: 16, languageCode: languageCode, weight: .semibold))
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
    var theme: GhafTheme? = nil
    @Environment(\.ghafCategoryMeta) private var meta
    @Environment(\.colorScheme) private var colorScheme

    /// Earthy palette drawn from the UAE (saffron, green, Gulf water, dates, henna), each with a
    /// lighter shade for dark mode so glyphs stay readable on dark cards.
    enum Palette: String {
        case saffron, green, gulf, ember, date, rose, coral, henna, sea, mint, stone, lavender

        var pair: (light: UInt32, dark: UInt32) {
            switch self {
            case .saffron: (0xC4741F, 0xF2A65A)
            case .green: (0x3E7B4C, 0x7FC48D)
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
        case "green": color(.green)
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

    /// Built-in categories: symbol and palette colour.
    static func builtIn(_ category: String) -> (symbol: String, palette: Palette)? {
        switch category {
        case "Groceries": ("basket.fill", .green)
        case "Dining": ("fork.knife", .saffron)
        case "Transport": ("car.fill", .gulf)
        case "Fuel": ("fuelpump.fill", .ember)
        case "Bills & Utilities": ("bolt.fill", .date)
        case "Shopping": ("bag.fill", .rose)
        case "Health": ("cross.case.fill", .coral)
        case "Entertainment": ("play.rectangle.fill", .henna)
        case "Travel": ("airplane", .sea)
        case "Salary": ("banknote.fill", .mint)
        case "Transfers": ("arrow.left.arrow.right", .stone)
        case "Subscriptions": ("repeat", .lavender)
        default: nil
        }
    }

    /// One stable colour per category for charts: its own, else a palette colour picked from its name.
    static func chartColor(_ category: String, dark: Bool) -> Color {
        let all: [Palette] = [.saffron, .gulf, .green, .rose, .henna, .sea, .date, .ember, .coral, .mint, .lavender, .stone]
        let palette = builtIn(category)?.palette ?? all[abs(category.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % all.count]
        let hex = dark ? palette.pair.dark : palette.pair.light
        return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Distinct colours for the categories shown together in one chart: built-in ones keep their own,
    /// the rest take palette colours nobody else in the chart uses.
    static func chartColors(for categories: [String], dark: Bool) -> [String: Color] {
        let all: [Palette] = [.saffron, .gulf, .green, .rose, .henna, .sea, .date, .ember, .coral, .mint, .lavender, .stone]
        var used = Set(categories.compactMap { builtIn($0)?.palette })
        var result: [String: Color] = [:]
        for category in categories {
            let palette = builtIn(category)?.palette ?? all.first { !used.contains($0) } ?? all[result.count % all.count]
            used.insert(palette)
            let hex = dark ? palette.pair.dark : palette.pair.light
            result[category] = Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        return result
    }

    private var style: (symbol: String, color: Color) {
        if let builtIn = Self.builtIn(category) { return (builtIn.symbol, color(builtIn.palette)) }
        // Imported categories ("Food", "Car", "Utilities"…) match the taxonomy by name or alias.
        let key = category.lowercased()
        if let match = CategoryTaxonomy.all.first(where: { $0.name.lowercased() == key || $0.aliases.contains { $0.lowercased() == key } }) {
            return (match.icon, color(named: match.color) ?? tint)
        }
        return ("creditcard.fill", tint)
    }

    var body: some View {
        let custom = meta[category]
        GhafIconBadge(symbol: custom?.icon ?? style.symbol,
                      tint: color(named: custom?.color) ?? style.color, theme: theme)
    }
}


// MARK: - 1.31 button behaviours (owner picks: ring loader, drawn check held 900 ms, split delete, Undo for 5 s)

/// A capsule button that runs async work: the label turns into a ring while it runs, then a drawn ✓ for 900 ms.
/// The ✓ only shows when `action` returns without throwing; a throw shakes the button and keeps the label.
struct GhafAsyncButton: View {
    let title: String
    let theme: GhafTheme
    let languageCode: String
    var role: GhafCapsuleButtonStyle.Role = .primary
    let action: () async throws -> Void
    @State private var phase = Phase.idle
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Phase { case idle, running, done }

    var body: some View {
        Button {
            guard phase == .idle else { return }
            phase = .running
            Task { @MainActor in
                do {
                    try await action()
                    withAnimation(.easeOut(duration: 0.2)) { phase = .done }
                    try? await Task.sleep(for: .milliseconds(900))
                    withAnimation(.easeOut(duration: 0.2)) { phase = .idle }
                } catch {
                    phase = .idle
                    shakes += 1
                }
            }
        } label: {
            ZStack {
                Text(title).opacity(phase == .idle ? 1 : 0)
                if phase == .running { ProgressView().tint(.primary).controlSize(.regular) }
                if phase == .done { GhafDrawnCheck(reduceMotion: reduceMotion).frame(width: 22, height: 22) }
            }
        }
        .buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: role))
        .modifier(GhafShake(amount: reduceMotion ? 0 : 8, shakes: CGFloat(shakes)))
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .done }
        .sensoryFeedback(.error, trigger: shakes)
        .accessibilityValue(phase == .running ? (languageCode == "ar" ? "جارٍ" : "In progress") : phase == .done ? (languageCode == "ar" ? "تم" : "Done") : "")
    }
}

/// A ✓ that draws itself left to right.
struct GhafDrawnCheck: View {
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0
    var body: some View {
        CheckShape()
        .trim(from: 0, to: progress)
        .stroke(style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { progress = 1 } }
    }
}

private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.55))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.40, y: r.minY + r.height * 0.80))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.88, y: r.minY + r.height * 0.22))
        }
    }
}

struct GhafShake: GeometryEffect {
    var amount: CGFloat
    var shakes: CGFloat
    var animatableData: CGFloat { get { shakes } set { shakes = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(shakes * .pi * 4), y: 0))
    }
}

/// Delete that splits in place into Cancel | Delete instead of opening a pop-up.
struct GhafSplitDeleteButton: View {
    let title: String
    let confirmTitle: String
    let theme: GhafTheme
    let languageCode: String
    let action: () -> Void
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        HStack(spacing: 10) {
            if armed {
                Button(ar ? "إلغاء" : "Cancel") { withAnimation(anim) { armed = false } }
                    .buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .secondary))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                Button(confirmTitle) { armed = false; action() }
                    .buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .destructive))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Button(title) { withAnimation(anim) { armed = true } }
                    .buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .destructive))
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.warning, trigger: armed) { _, new in new }
        // Walking away disarms it, so a later stray tap can't delete.
        .task(id: armed) { if armed { try? await Task.sleep(for: .seconds(4)); withAnimation(anim) { armed = false } } }
    }
    private var anim: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1) }
}

/// After an edit or delete: a Done | Undo pair for 5 s, then it goes away. Undo must restore exactly what changed.
struct GhafUndoBar: View {
    let message: String
    let theme: GhafTheme
    let languageCode: String
    let undo: () -> Void
    let finished: () -> Void
    @State private var remaining: CGFloat = 1
    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(ar ? "تراجع" : "Undo") { undo(); finished() }
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.ghafPress)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(theme.surface, in: Capsule())
        .overlay(alignment: .bottom) {
            Capsule().fill(theme.accent.opacity(0.5)).frame(height: 2).scaleEffect(x: remaining, anchor: .leading).padding(.horizontal, 24)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .onAppear { withAnimation(.linear(duration: 5)) { remaining = 0 } }
        .task { try? await Task.sleep(for: .seconds(5)); finished() }
        .accessibilityElement(children: .contain)
    }
}
