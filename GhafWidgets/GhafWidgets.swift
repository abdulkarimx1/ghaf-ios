import WidgetKit
import SwiftUI
import ActivityKit
import UIKit

#if WIDGET_EXTENSION
@main
#endif
struct GhafWidgetBundle: WidgetBundle {
    var body: some Widget {
        GhafBalanceWidget()
        GhafTodayWidget()
        GhafRecentWidget()
        GhafSpendingWidget()
        GhafBudgetWidget()
        GhafCategoriesWidget()
        GhafBillsWidget()
        GhafTrendsWidget()
        GhafQuickAddWidget()
        GhafAskWidget()
        GhafMoneyTipWidget()
        GhafStreakWidget()
        GhafTopPlacesWidget()
        GhafBudgetPetalsWidget()
        GhafPurchaseLiveActivity()
    }
}

/// Pro entitlement is shared through the app group so the extension can gate premium content.
enum GhafWidgetProAccess {
    static let key = "ghaf.pro.unlocked"
    static var unlocked: Bool {
        GhafWidgetSnapshot.groupIDs.contains { UserDefaults(suiteName: $0)?.bool(forKey: key) == true }
    }
}

/// True inside the in-app widget gallery: V17, everyone sees every widget; only using one on the Home Screen needs Pro.
private struct GhafWidgetPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ghafWidgetPreview: Bool {
        get { self[GhafWidgetPreviewKey.self] }
        set { self[GhafWidgetPreviewKey.self] = newValue }
    }
}

struct GhafWidgetProLock<Peek: View>: ViewModifier {
    let required: Bool
    let isArabic: Bool?
    @ViewBuilder let peek: () -> Peek
    @Environment(\.ghafWidgetPreview) private var preview

    init(required: Bool, isArabic: Bool? = nil, @ViewBuilder peek: @escaping () -> Peek) {
        self.required = required
        self.isArabic = isArabic
        self.peek = peek
    }

    func body(content: Content) -> some View {
        if required && !preview && !GhafWidgetProAccess.unlocked {
            ZStack {
                peek()
                    .blur(radius: 12)
                    .opacity(0.3)
                    .accessibilityHidden(true)
                GhafWidgetProMask(isArabic: isArabic)
                    .environment(\.layoutDirection, isArabic == true ? .rightToLeft : .leftToRight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { GhafWidgetProSurface() }
            // Small widgets ignore Link; the whole tile opens Pro.
            .widgetURL(URL(string: "ghaf://pro"))
            .overlay {
                Link(destination: URL(string: "ghaf://pro")!) {
                    Color.clear.contentShape(ContainerRelativeShape())
                }
                .accessibilityLabel(isArabic == true ? "افتح غاف برو" : "Unlock Ghaf Pro")
            }
        } else { content }
    }
}

private struct GhafWidgetProSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }
    private var surface: Color { dark ? ink : paper }

    var body: some View {
        GeometryReader { geometry in
            let radius = hypot(geometry.size.width, geometry.size.height) * 0.7
            ZStack {
                ContainerRelativeShape().fill(surface)
                RadialGradient(colors: [
                    (dark ? Color.white : Color.gray).opacity(0.08),
                    .clear
                ], center: .topLeading, startRadius: 0, endRadius: radius)
                ContainerRelativeShape()
                    .strokeBorder((dark ? Color.white : Color.black).opacity(dark ? 0.10 : 0.06), lineWidth: 0.5)
            }
            .clipShape(ContainerRelativeShape())
        }
    }
}

/// Shared, legible lock treatment used on every Pro-gated widget.
struct GhafWidgetProMask: View {
    @Environment(\.locale) private var locale
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let isArabic: Bool?
    private var arabic: Bool { isArabic ?? (locale.language.languageCode?.identifier == "ar") }

    private var badge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background(.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5))
            .widgetAccentable()
    }

    private func labels(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("Ghaf Pro")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .widgetAccentable()
            Text(arabic ? "افتحها من التطبيق" : "Unlock in the app")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .fontDesign(.default)
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 12) {
                    badge
                    labels(.leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    badge
                    labels(.center)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(.primary)
        .fontDesign(.default)
        .padding(.horizontal, family == .systemMedium ? 16 : 8)
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
        .contentShape(Rectangle())
    }
}

// MARK: Timeline

struct GhafEntry: TimelineEntry {
    let date: Date
    let snapshot: GhafWidgetSnapshot?
}

struct GhafProvider: TimelineProvider {
    func placeholder(in context: Context) -> GhafEntry { GhafEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (GhafEntry) -> Void) {
        completion(GhafEntry(date: .now, snapshot: context.isPreview ? .sample : GhafWidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GhafEntry>) -> Void) {
        // Ghaf reloads the widgets whenever a transaction is recorded; midnight resets "today".
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        let loaded = GhafWidgetSnapshot.loadWithSource()
        GhafWidgetSnapshot.recordHeartbeat(family: String(describing: context.family), kind: "GhafToday", source: loaded.source)
        completion(Timeline(entries: [GhafEntry(date: .now, snapshot: loaded.snapshot)], policy: .after(midnight)))
    }
}

extension GhafWidgetSnapshot {
    /// Gallery preview only (WidgetKit's isPreview / placeholder); real widgets always read the app's snapshot.
    #if DEBUG
    static var sampleDateOverride: Date?
    #endif
    static var sample: GhafWidgetSnapshot {
        let now: Date
        #if DEBUG
        now = sampleDateOverride ?? .now
        #else
        now = .now
        #endif
        var s = GhafWidgetSnapshot(currency: "AED", balance: 12_450, spentToday: 86.5, spentThisMonth: 2_310,
                                   lastPurchase: .init(merchant: "Carrefour", amount: 45, currency: "AED", date: now.addingTimeInterval(-1_500)),
                                   hidden: false, arabic: false, updated: now,
                                   todayCategories: [.init(name: "Groceries", amount: 45), .init(name: "Dining", amount: 28.5), .init(name: "Transport", amount: 13)],
                                   lastSevenDays: [120, 60, 210, 90, 40, 150, 86.5])
        let categories: [CategorySpend] = [.init(name: "Groceries", amount: 420, symbol: "basket.fill"), .init(name: "Dining", amount: 310, symbol: "fork.knife"),
                                           .init(name: "Transport", amount: 180, symbol: "car.fill"), .init(name: "Shopping", amount: 90, symbol: "bag.fill")]
        let far = Date.distantFuture
        s.day = .init(end: far, spent: 86.5, previous: 150, count: 3, bars: [0, 0, 0, 12, 45, 28.5, 0, 0], categories: Array(categories.prefix(2)))
        s.week = .init(end: far, spent: 756.5, previous: 910, count: 14, bars: [120, 60, 210, 90, 40, 150, 86.5], categories: categories)
        s.month = .init(end: far, spent: 2_310, previous: 2_640, count: 41, bars: [640, 820, 610, 240, 0], categories: categories)
        s.recent = .init(merchant: "Carrefour", category: "Groceries", symbol: "basket.fill", amount: 45, currency: "AED", date: now.addingTimeInterval(-1_500),
                         isCredit: false, account: "Mashreq", bank: "Mashreq", needsReview: false)
        s.budget = .init(limit: 9_000, spent: 3_150, title: "Monthly budget", end: far)
        s.streak = .init(days: 12, week: [true, true, false, true, true, true, true])
        s.places = [.init(name: "Dubai Marina", amount: 640), .init(name: "Downtown Dubai", amount: 410), .init(name: "JLT", amount: 180)]
        s.petals = [.init(name: "Groceries", spent: 420, budget: 900, fill: 0.16 + 0.64 * 0.47, over: false),
                    .init(name: "Dining", spent: 310, budget: 300, fill: 0.8, over: true),
                    .init(name: "Transport", spent: 180, budget: 400, fill: 0.16 + 0.64 * 0.45, over: false),
                    .init(name: "Shopping", spent: 25, budget: 1_200, fill: 0.16 + 0.84 * 0.08, over: false)]
        s.overColor = 0xFF7A6B
        s.upcoming = [.init(name: "Netflix", amount: 39, currency: "AED", date: now.addingTimeInterval(2 * 86_400), symbol: "play.tv.fill"),
                      .init(name: "iCloud+", amount: 10.99, currency: "AED", date: now.addingTimeInterval(5 * 86_400), symbol: "icloud.fill")]
        return s
    }

    static func proPreview(arabic: Bool?) -> GhafWidgetSnapshot {
        var sample = Self.sample
        sample.arabic = arabic ?? (Locale.current.language.languageCode?.identifier == "ar")
        sample.hidden = false
        return sample
    }
}

// Near-black tiles lit by the user's city theme (sent by the app); sand-gold until the app has written one.
let ink = Color(red: 0.05, green: 0.05, blue: 0.06)
let paper = Color(red: 0.95, green: 0.95, blue: 0.95)

struct GhafWidgetBackground: View {
    let tile: GhafTile
    let enabled: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode
    private static let grain: UIImage? = {
        let n = 64
        var seed: UInt32 = 0x47484146
        let data = (0..<(n * n)).map { _ -> UInt8 in seed = 1664525 &* seed &+ 1013904223; return UInt8(seed >> 24) }
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }()
    var body: some View {
        let glass = enabled && renderingMode == .fullColor
        ZStack(alignment: .bottom) {
            tile.background
            if glass {
                LinearGradient(colors: [tile.background.opacity(0.65), tile.background.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [.clear, tile.highlight.opacity(0.38)], startPoint: .top, endPoint: .bottom).frame(height: 40)
                if let grain = Self.grain {
                    Image(uiImage: grain).resizable(resizingMode: .tile).opacity(0.035).blendMode(.overlay).allowsHitTesting(false)
                }
                RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.05), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        }
    }
}

extension GhafWidgetSnapshot {
    var accentColor: Color { Color(ghafHex: accent ?? 0xE0B472) }
    var glowColor: Color { Color(ghafHex: glow ?? 0xF3D29A) }
    /// Category colours: the theme's two, then two neutrals that read on the accent tile.
    var categoryColors: [Color] { [ink, ink.opacity(0.55), paper, ink.opacity(0.3)] }
}

func text(_ snapshot: GhafWidgetSnapshot?, _ en: String, _ ar: String) -> String { snapshot?.arabic == true ? ar : en }

/// Small caps caption used on every tile.
struct Caption: View {
    let value: String
    private var isArabic: Bool {
        value.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) || (0x0750...0x077F).contains(Int($0.value)) }
    }
    var body: some View {
        Text(isArabic ? value : value.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(isArabic ? 0 : 0.6)
            .lineLimit(1)
    }
}

/// Seven daily bars, today highlighted. Heights are relative to the week's largest day.
struct WeekBars: View {
    let days: [Decimal]
    let base: Color
    let highlight: Color
    /// The highlighted bar (the current slice); the last one when nil.
    var current: Int? = nil
    var height: CGFloat = 30
    var body: some View {
        let peak = max(days.max() ?? 0, 1)
        let lit = current ?? days.count - 1
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == lit ? highlight : base)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(NSDecimalNumber(decimal: value / peak).doubleValue) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

struct OpenGhaf: View {
    let ink: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up.forward.app").font(.system(size: 18, weight: .semibold))
            Text("Open Ghaf to load your numbers").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            // What this widget can reach, so a sideloaded install with mismatched sharing can be diagnosed.
            Text("Widget · group \(GhafWidgetSnapshot.hasSharedContainer ? "✓" : "✗") \(GhafWidgetSnapshot.groupID) · keychain \(GhafWidgetKeychain.read() != nil ? "✓" : (GhafWidgetKeychain.accessGroup == nil ? "✗" : "empty"))")
                .font(ghafNumberFont(8, weight: .medium))
                .multilineTextAlignment(.center)
                .opacity(0.6)
        }
        .foregroundStyle(ink)
    }
}

// MARK: Balance widget

struct GhafBalanceWidget: Widget {
    static let kind = "GhafBalance"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafBalanceConfig.self, provider: GhafConfigProvider<GhafBalanceConfig>(kind: Self.kind)) { entry in
            GhafBalanceView(entry: entry).ghafTap(Self.kind, entry.config.onTap).fontDesign(entry.config.font.design)
                .containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.snapshot?.glass ?? false) }
        }
        .configurationDisplayName("Balance")
        .description("Your total balance and this week's spending.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct GhafBalanceView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var galleryFamily: WidgetFamily? = nil
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    let entry: GhafConfigEntry<GhafBalanceConfig>

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        // Tapping (when set to switch view) swaps the big number between the balance and this month's spending.
        let showSpent = entry.config.onTap == .switchView && GhafNextViewIntent.count(GhafBalanceWidget.kind) % 2 == 1
        if let s = entry.snapshot {
            let hero: Decimal? = showSpent ? s.spentThisMonth : s.balance
            let caption = showSpent ? text(s, "Spent · month · ", "صرفت · الشهر · ") : text(s, "Balance · ", "الرصيد · ")
            switch family {
            case .accessoryInline:
                Text(hero.map { s.money($0) } ?? text(s, "Open Ghaf", "افتح غاف"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Caption(value: showSpent ? text(s, "Spent this month", "صرف الشهر") : text(s, "Balance", "الرصيد"))
                    Text(hero.map { s.money($0) } ?? "—").font(.headline).minimumScaleFactor(0.6).privacySensitive()
                    Text(text(s, "Month ", "الشهر ") + s.money(s.spentThisMonth)).font(.caption2).privacySensitive()
                }
            default:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Caption(value: caption + s.currency).foregroundStyle(tile.dim)
                        Spacer(minLength: 0)
                        if family == .systemSmall, entry.config.showWeek, let week = s.lastSevenDays { WeekBars(days: week, base: tile.foreground.opacity(0.14), highlight: tile.highlight) }
                        Text(hero.map { s.hidden ? "✦✦✦✦" : $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                            .font(.system(size: family == .systemSmall ? 30 : 36, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(tile.foreground)
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.numericText())
                            .privacySensitive()
                        Text(text(s, "Spent ", "صرفت ") + s.money(s.spentThisMonth) + text(s, " this month", " هذا الشهر"))
                            .font(ghafNumberFont(11, weight: .bold))
                            .foregroundStyle(tile.highlight)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .privacySensitive()
                    }
                    if family == .systemMedium, entry.config.showWeek, let week = s.lastSevenDays {
                        VStack(alignment: .leading, spacing: 6) {
                            Caption(value: text(s, "Last 7 days", "آخر ٧ أيام")).foregroundStyle(tile.dim)
                            Spacer(minLength: 0)
                            WeekBars(days: week, base: tile.foreground.opacity(0.14), highlight: tile.highlight).frame(height: 60)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
            }
        } else {
            OpenGhaf(ink: family == .systemSmall || family == .systemMedium ? tile.foreground : .primary)
        }
    }
}

// MARK: Today widget

struct GhafTodayWidget: Widget {
    static let kind = "GhafToday"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafTodayConfig.self, provider: GhafConfigProvider<GhafTodayConfig>(kind: Self.kind)) { entry in
            GhafTodayView(entry: entry).ghafTap(Self.kind, entry.config.onTap).fontDesign(entry.config.font.design)
                .containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.snapshot?.glass ?? false) }
                .modifier(GhafWidgetProLock(required: true, isArabic: entry.snapshot?.arabic) {
                    GhafTodayView(entry: .init(date: entry.date, snapshot: .proPreview(arabic: entry.snapshot?.arabic), config: entry.config))
                })
        }
        .configurationDisplayName("Today")
        .description("What you spent today, by category.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct GhafTodayView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var galleryFamily: WidgetFamily? = nil
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    let entry: GhafConfigEntry<GhafTodayConfig>

    /// The snapshot with today's numbers swapped for the week's or month's, when the widget has been tapped on.
    private static func shown(_ snapshot: GhafWidgetSnapshot?, _ period: GhafWidgetPeriod, at date: Date) -> GhafWidgetSnapshot? {
        guard period != .day, var patched = snapshot, let shown = patched.shown(period, at: date) else { return snapshot }
        patched.spentToday = shown.spent
        patched.todayCategories = shown.categories
        return patched
    }

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        // Tapping (when set to switch view) steps today → this week → this month; the numbers come from that period.
        let period = ghafStepped([GhafWidgetPeriod.day, .week, .month], start: .day, kind: GhafTodayWidget.kind, tap: entry.config.onTap)
        let s = Self.shown(entry.snapshot, period, at: entry.date)
        let caption = period == .day ? text(s, "Spent today", "صرف اليوم") : text(s, "Spent · ", "صرفت · ") + periodName(period, s)
        if family == .accessoryCircular {
            // Budget ring: how much of today's budget is spent. Without a daily budget it shows today's spend only.
            let used = s?.dailyBudgetUsed
            Gauge(value: min(max(used ?? 0, 0), 1)) {
                Text(s?.currency ?? "AED")
            } currentValueLabel: {
                Text(used.map { $0.formatted(.percent.precision(.fractionLength(0))) }
                     ?? s.map { $0.hidden ? "✦✦" : $0.spentToday.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .minimumScaleFactor(0.5)
                    .privacySensitive()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(used.map { text(s, "Budget \(Int(($0 * 100).rounded())) percent used", "استُخدم \(Int(($0 * 100).rounded())) بالمئة من الميزانية") }
                                ?? text(s, "Spent today", "صرف اليوم"))
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Caption(value: caption).opacity(0.7)
                Text(s.map { $0.money($0.spentToday) } ?? "—")
                    .font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let s {
            if family == .systemMedium { medium(s, tile, caption, now: entry.date) } else { small(s, tile, caption) }
        } else {
            OpenGhaf(ink: tile.foreground)
        }
    }

    private func small(_ s: GhafWidgetSnapshot, _ tile: GhafTile, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(value: caption).foregroundStyle(tile.dim)
            Text(s.hidden ? "✦✦✦" : s.spentToday.formatted(.number.precision(.fractionLength(0))))
                .font(.system(size: 40, weight: .heavy)).tracking(-1.2)
                .foregroundStyle(tile.foreground).minimumScaleFactor(0.5).lineLimit(1)
                .privacySensitive()
            Spacer(minLength: 0)
            if let week = s.lastSevenDays { WeekBars(days: week, base: tile.foreground.opacity(0.18), highlight: tile.highlight) }
            Text(s.currency + text(s, " · this week", " · هذا الأسبوع")).font(.system(size: 11, weight: .bold)).foregroundStyle(tile.foreground.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
    }

    private func medium(_ s: GhafWidgetSnapshot, _ tile: GhafTile, _ caption: String, now: Date) -> some View {
        let categories = s.todayCategories ?? []
        let total = max(categories.reduce(Decimal.zero) { $0 + $1.amount }, 1)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Caption(value: caption).foregroundStyle(tile.dim)
                Text(s.money(s.spentToday)).font(ghafNumberFont(26, weight: .heavy)).tracking(-0.8)
                    .foregroundStyle(tile.foreground).minimumScaleFactor(0.5).lineLimit(1).privacySensitive()
                Spacer(minLength: 0)
                if let last = s.lastPurchase {
                    Text(text(s, "Last: ", "آخر عملية: ") + last.merchant).font(.system(size: 11, weight: .bold)).lineLimit(1).privacySensitive()
                    Text(relativeDateText(last.date, now: now, locale: s.locale)).font(.system(size: 11)).foregroundStyle(tile.foreground.opacity(0.6))
                }
            }
            .foregroundStyle(tile.foreground)
            VStack(alignment: .leading, spacing: 5) {
                if categories.isEmpty {
                    Text(text(s, "No spending yet today", "لا صرف اليوم بعد")).font(.caption.weight(.semibold)).foregroundStyle(tile.foreground.opacity(0.6))
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(categories.enumerated()), id: \.offset) { i, c in
                                Capsule().fill(tile.palette[i % tile.palette.count])
                                    .frame(width: max(4, geo.size.width * CGFloat(NSDecimalNumber(decimal: c.amount / total).doubleValue) - 2))
                            }
                        }
                    }
                    .frame(height: 6)
                    ForEach(Array(categories.enumerated()), id: \.offset) { i, c in
                        HStack(spacing: 6) {
                            Circle().fill(tile.palette[i % tile.palette.count]).frame(width: 6, height: 6)
                            Text(c.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(s.hidden ? "✦✦" : c.amount.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: s.currency))))).privacySensitive()
                        }
                        .font(ghafNumberFont(11, weight: .semibold))
                        .foregroundStyle(tile.foreground)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
    }

    private func relativeDateText(_ date: Date, now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: Live Activity: a purchase just recorded
// One at a time (a new purchase replaces the last), stale after five minutes.
// Lock Screen is the main surface; the Dynamic Island shows compact (symbol + amount), minimal (symbol only,
// fits the 28 pt circle) and expanded (who, what, how much, which account).

private extension GhafPurchaseAttributes {
    var accentColor: Color { Color(ghafHex: accent) }
    var glowColor: Color { Color(ghafHex: glow) }
    var gradient: LinearGradient { LinearGradient(colors: [glowColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

private extension GhafPurchaseAttributes.ContentState {
    var signedAmount: String {
        hidden == true ? "✦✦✦" : (isCredit ? "+" : "−") + currency + " " + amount.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: currency))))
    }
    var shortAmount: String { signedAmount }
    var transactionURL: URL? { transactionID.flatMap { URL(string: "ghaf://transaction/\($0.uuidString)") } }
    func spoken(_ arabic: Bool) -> String {
        if hidden == true { return arabic ? "عملية جديدة، \(merchant)" : "New transaction, \(merchant)" }
        return arabic ? "\(isCredit ? "وصلك" : "دفعت") \(amount.formatted()) \(currency)، \(merchant)"
               : "\(isCredit ? "Received" : "Paid") \(currency) \(amount.formatted()), \(merchant)"
    }
}

/// The category glyph on the theme gradient.
private struct GhafCategoryBadge: View {
    let state: GhafPurchaseAttributes.ContentState
    let attributes: GhafPurchaseAttributes
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(attributes.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Recorded 14:05", or "Needs review" when Ghaf was unsure.
private struct GhafActivityStatus: View {
    let context: ActivityViewContext<GhafPurchaseAttributes>
    var body: some View {
        let s = context.state
        let ar = context.attributes.arabic
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.accountName ?? (ar ? "البطاقة" : "Card")).lineLimit(1).privacySensitive()
                if let at = s.recordedAt { Text(at, style: .time).lineLimit(1) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(paper.opacity(0.62))
            Spacer(minLength: 4)
            if let balance = s.balance {
                Text(ar ? "الرصيد · \(s.currency) \(balance.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: s.currency)))))" : "Balance · \(s.currency) \(balance.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: s.currency)))))")
                    .lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
            }
            if let url = s.transactionURL {
                Link(ar ? "فتح" : "Open", destination: url).font(.caption.weight(.bold)).foregroundStyle(context.attributes.glowColor)
            }
        }
        if let recordedAt = s.recordedAt, let expiresAt = s.expiresAt, expiresAt > recordedAt {
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(timerInterval: recordedAt...expiresAt, countsDown: true)
                    .progressViewStyle(.linear).labelsHidden().tint(context.attributes.glowColor)
                    .frame(maxWidth: .infinity)
                Text(timerInterval: recordedAt...expiresAt, countsDown: true)
                    .font(.caption2.monospacedDigit()).foregroundStyle(paper.opacity(0.62))
            }
                .accessibilityLabel(ar ? "ينتهي النشاط قريبًا" : "Activity time remaining")
        }
    }
}

struct GhafPurchaseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GhafPurchaseAttributes.self) { context in
            GhafPurchaseLockView(context: context)
                .activityBackgroundTint(ink.opacity(0.92))
                .activitySystemActionForegroundColor(paper)
        } dynamicIsland: { context in
            let s = context.state
            let a = context.attributes
            let fade = context.isStale ? 0.55 : 1
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        GhafCategoryBadge(state: s, attributes: a, size: 42)
                        Text(s.merchant).font(.subheadline.weight(.semibold)).foregroundStyle(paper)
                            .lineLimit(2).minimumScaleFactor(0.82).fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1).privacySensitive()
                    }
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(s.signedAmount)
                            .font(ghafNumberFont(24, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(s.isCredit ? Color.green : paper)
                            .minimumScaleFactor(0.6).lineLimit(1).privacySensitive()
                    }
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                    .padding(.trailing, 4)
                    .opacity(fade)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 3) {
                        Text(s.accountName ?? (a.arabic ? "البطاقة" : "Card")).font(.caption.weight(.semibold)).lineLimit(1).privacySensitive()
                        if let at = s.recordedAt { Text(at, style: .time).font(.caption2).foregroundStyle(paper.opacity(0.6)) }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Spacer(minLength: 0); GhafActivityStatus(context: context); Spacer(minLength: 0) }
                        .padding(.horizontal, 4).padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: s.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(a.gradient)
                    .accessibilityLabel(s.category)
            } compactTrailing: {
                Text(s.shortAmount)
                    .font(ghafNumberFont(14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(s.isCredit ? Color.green : a.glowColor)
                    .opacity(fade).privacySensitive()
                    .accessibilityLabel(s.spoken(a.arabic))
            } minimal: {
                Image(systemName: s.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(a.gradient)
                    .accessibilityLabel(s.spoken(a.arabic))
            }
            .keylineTint(a.glowColor)
        }
    }
}

struct GhafPurchaseLockView: View {
    let context: ActivityViewContext<GhafPurchaseAttributes>

    var body: some View {
        let s = context.state
        let a = context.attributes
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GhafCategoryBadge(state: s, attributes: a, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.merchant).font(.system(size: 16, weight: .semibold)).foregroundStyle(paper)
                        .lineLimit(2).minimumScaleFactor(0.82).fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1).privacySensitive()
                    Text(s.category)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(paper.opacity(0.6)).lineLimit(1).privacySensitive()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(s.signedAmount)
                        .font(ghafNumberFont(26, weight: .heavy)).tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(s.isCredit ? Color.green : paper)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText()).privacySensitive()
                }
                .opacity(context.isStale ? 0.55 : 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(s.spoken(a.arabic))
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.accountName ?? (a.arabic ? "البطاقة" : "Card")).font(.caption.weight(.semibold)).privacySensitive()
                    if let at = s.recordedAt { Text(at, style: .time).font(.caption2).foregroundStyle(paper.opacity(0.6)) }
                }
                Spacer(minLength: 6)
                if let balance = s.balance {
                    Text((a.arabic ? "الرصيد · " : "Balance · ") + s.currency + " " + balance.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: s.currency)))))
                        .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
                }
                if let url = s.transactionURL { Link(a.arabic ? "فتح" : "Open", destination: url).font(.caption.weight(.bold)).foregroundStyle(a.glowColor) }
            }
            if let recordedAt = s.recordedAt, let expiresAt = s.expiresAt, expiresAt > recordedAt {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(timerInterval: recordedAt...expiresAt, countsDown: true)
                        .progressViewStyle(.linear).labelsHidden().tint(a.glowColor)
                        .frame(maxWidth: .infinity)
                    Text(timerInterval: recordedAt...expiresAt, countsDown: true)
                        .font(.caption2.monospacedDigit()).foregroundStyle(paper.opacity(0.62))
                }
                    .accessibilityLabel(a.arabic ? "ينتهي النشاط قريبًا" : "Activity time remaining")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .environment(\.layoutDirection, a.arabic ? .rightToLeft : .leftToRight)
    }
}

#Preview("Lock Screen", as: .content, using: GhafPurchaseAttributes(arabic: false, accent: 0xE0B472, glow: 0xF3D29A)) {
    GhafPurchaseLiveActivity()
} contentStates: {
    GhafPurchaseAttributes.ContentState(merchant: "Carrefour", amount: 45.5, currency: "AED", isCredit: false, accountName: "Mashreq",
                                        balance: 12_404.5, needsReview: false, symbol: "basket.fill", category: "Groceries", recordedAt: .now)
    GhafPurchaseAttributes.ContentState(merchant: "ENOC", amount: 1_250, currency: "AED", isCredit: false, accountName: nil,
                                        balance: nil, needsReview: true, symbol: "fuelpump.fill", category: "Fuel", recordedAt: .now)
}
