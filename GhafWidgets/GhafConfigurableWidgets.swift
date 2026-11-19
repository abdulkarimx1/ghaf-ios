import WidgetKit
import SwiftUI
import AppIntents

// Five configurable widgets (1.20). Every number comes from the snapshot the app writes from the ledger;
// the widget only picks which part to show and notices when a period has ended since the app last wrote.

// MARK: Shared pieces

struct GhafConfigEntry<Config: WidgetConfigurationIntent>: TimelineEntry {
    let date: Date
    let snapshot: GhafWidgetSnapshot?
    let config: Config
}

struct GhafConfigProvider<Config: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    let kind: String
    func placeholder(in context: Context) -> GhafConfigEntry<Config> { .init(date: .now, snapshot: .sample, config: Config()) }
    func snapshot(for configuration: Config, in context: Context) async -> GhafConfigEntry<Config> {
        let snapshot: GhafWidgetSnapshot?
        let source: String
        if context.isPreview { snapshot = .sample; source = "none" }
        else { let loaded = GhafWidgetSnapshot.loadWithSource(); snapshot = loaded.snapshot; source = loaded.source }
        if !context.isPreview { GhafWidgetSnapshot.recordHeartbeat(family: String(describing: context.family), kind: kind, source: source) }
        return .init(date: .now, snapshot: snapshot, config: configuration)
    }
    func timeline(for configuration: Config, in context: Context) async -> Timeline<GhafConfigEntry<Config>> {
        // The app reloads widgets on every recorded transaction; midnight rolls "today" over and moves due dates.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        let loaded = GhafWidgetSnapshot.loadWithSource()
        GhafWidgetSnapshot.recordHeartbeat(family: String(describing: context.family), kind: kind, source: loaded.source)
        return Timeline(entries: [.init(date: .now, snapshot: loaded.snapshot, config: configuration)], policy: .after(midnight))
    }
}

// MARK: Tap behaviour

private struct GhafSwitchTapKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True while the whole widget is one "switch view" button; inner buttons turn into plain labels then.
    var ghafSwitchTap: Bool {
        get { self[GhafSwitchTapKey.self] }
        set { self[GhafSwitchTapKey.self] = newValue }
    }
}

extension View {
    /// "Open Ghaf" leaves the default tap (opens the app). "Switch view" makes the whole widget step to its next view.
    @ViewBuilder func ghafTap(_ kind: String, _ tap: GhafWidgetTap) -> some View {
        if tap == .switchView {
            Button(intent: GhafNextViewIntent(kind: kind)) { environment(\.ghafSwitchTap, true) }.buttonStyle(.plain)
        } else {
            self
        }
    }
}

/// The value after `GhafNextViewIntent.count` taps, walking `all` from `start`; unchanged unless the widget switches on tap.
func ghafStepped<T: Equatable>(_ all: [T], start: T, kind: String, tap: GhafWidgetTap) -> T {
    guard tap == .switchView, let i = all.firstIndex(of: start) else { return start }
    return all[(i + GhafNextViewIntent.count(kind)) % all.count]
}

/// The period a day/week/month widget shows: the Day/Week/Month chip choice, or the tap-cycled one.
func ghafSelectedPeriod(_ kind: String, configured: GhafWidgetPeriod, tap: GhafWidgetTap) -> GhafWidgetPeriod {
    tap == .switchView
        ? ghafStepped([.day, .week, .month], start: configured, kind: kind, tap: tap)
        : GhafSelectPeriodIntent.current(kind, configured: configured)
}

/// Colours for a tile: the dark ink tile lit by the theme, or the theme-coloured tile with ink text.
struct GhafTile {
    let background: Color, foreground: Color, highlight: Color
    let palette: [Color]
    let isDark: Bool

    init(_ style: GhafWidgetStyle, _ s: GhafWidgetSnapshot?) {
        let accent = s?.accentColor ?? Color(ghafHex: 0xE0B472)
        let glow = s?.glowColor ?? Color(ghafHex: 0xF3D29A)
        isDark = style == .ink || style == .midnight
        switch style {
        case .ink:
            background = ink; foreground = paper; highlight = accent
            palette = [accent, glow, paper.opacity(0.75), paper.opacity(0.45), paper.opacity(0.25)]
        case .theme:
            background = accent; foreground = ink; highlight = ink
            palette = [ink, ink.opacity(0.6), paper, ink.opacity(0.35), paper.opacity(0.6)]
        case .light:
            background = paper; foreground = ink; highlight = accent
            palette = [accent, glow, ink.opacity(0.75), ink.opacity(0.45), ink.opacity(0.2)]
        case .midnight:
            background = Color(ghafHex: 0x10162B); foreground = paper; highlight = glow
            palette = [glow, accent, paper.opacity(0.75), paper.opacity(0.45), paper.opacity(0.25)]
        }
    }
    var dim: Color { foreground.opacity(0.6) }
}

/// What a widget shows for one period, after checking it is still the current one.
struct GhafShownPeriod {
    var spent: Decimal
    var previous: Decimal?
    var count: Int
    var bars: [Decimal]
    var categories: [GhafWidgetSnapshot.CategorySpend]
    /// The bar for "now", so the current hour block / day / week is highlighted.
    var current: Int?
}

extension GhafWidgetSnapshot {
    func shown(_ period: GhafWidgetPeriod, at date: Date) -> GhafShownPeriod? {
        let stored: Period? = switch period { case .day: day; case .week: week; case .month: month }
        guard let stored else { return nil }
        if date >= stored.end {
            // A new period began and Ghaf has recorded nothing since (it rewrites the snapshot on every transaction).
            return GhafShownPeriod(spent: 0, previous: nil, count: 0, bars: stored.bars.map { _ in 0 }, categories: [], current: 0)
        }
        let length = stored.end.timeIntervalSince(GhafWidgetSnapshot.start(of: period, end: stored.end))
        let elapsed = length - stored.end.timeIntervalSince(date)
        let index = length > 0 ? min(stored.bars.count - 1, max(0, Int(elapsed / length * Double(stored.bars.count)))) : nil
        return GhafShownPeriod(spent: stored.spent, previous: stored.previous, count: stored.count,
                               bars: stored.bars, categories: stored.categories, current: index)
    }

    /// The last seven days as of `date`: days that passed since the app wrote the snapshot had no spending recorded.
    func lastSevenDays(at date: Date) -> [Decimal]? {
        guard let days = lastSevenDays else { return nil }
        let calendar = Calendar.current
        let passed = calendar.dateComponents([.day], from: calendar.startOfDay(for: updated), to: calendar.startOfDay(for: date)).day ?? 0
        let shift = min(max(passed, 0), days.count)
        return Array(days.dropFirst(shift)) + Array(repeating: 0, count: shift)
    }

    static func start(of period: GhafWidgetPeriod, end: Date) -> Date {
        let unit: Calendar.Component = switch period { case .day: .day; case .week: .weekOfYear; case .month: .month }
        return Calendar.current.date(byAdding: unit, value: -1, to: end) ?? end
    }

    /// Whole-number amount for big type, stars while balances are hidden.
    func whole(_ value: Decimal) -> String {
        hidden ? "✦✦✦" : value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
    var locale: Locale { Locale(identifier: arabic ? "ar_AE" : "en_AE") }
}

func periodName(_ p: GhafWidgetPeriod, _ s: GhafWidgetSnapshot?) -> String {
    switch p {
    case .day: text(s, "Today", "اليوم")
    case .week: text(s, "This week", "هذا الأسبوع")
    case .month: text(s, "This month", "هذا الشهر")
    }
}

func lastPeriodName(_ p: GhafWidgetPeriod, _ s: GhafWidgetSnapshot?) -> String {
    switch p {
    case .day: text(s, "yesterday", "أمس")
    case .week: text(s, "last week", "الأسبوع الماضي")
    case .month: text(s, "last month", "الشهر الماضي")
    }
}

/// Day · Week · Month switch. Each chip is a button that flips the widget without opening Ghaf.
struct PeriodSwitch: View {
    @Environment(\.ghafSwitchTap) private var passive
    var short = false
    let kind: String
    let configured: GhafWidgetPeriod
    let selected: GhafWidgetPeriod
    let tile: GhafTile
    let snapshot: GhafWidgetSnapshot?

    var body: some View {
        HStack(spacing: 4) {
            ForEach([GhafWidgetPeriod.day, .week, .month], id: \.self) { p in
                let chip = Text(label(p))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .foregroundStyle(p == selected ? tile.background : tile.foreground)
                    .background(p == selected ? tile.foreground : tile.foreground.opacity(0.12), in: Capsule())
                Group {
                    if passive { chip } else {
                        Button(intent: GhafSelectPeriodIntent(kind: kind, configured: configured, period: p)) { chip }.buttonStyle(.plain)
                    }
                }
                .accessibilityLabel(periodName(p, snapshot))
                .accessibilityAddTraits(p == selected ? .isSelected : [])
            }
        }
    }

    private func label(_ p: GhafWidgetPeriod) -> String {
        if short && snapshot?.arabic != true { return p == .day ? "1D" : p == .week ? "1W" : "1M" }
        switch p {
        case .day: return text(snapshot, "Day", "يوم")
        case .week: return text(snapshot, "Week", "أسبوع")
        case .month: return text(snapshot, "Month", "شهر")
        }
    }
}

/// A round refresh button for widgets whose view does not switch.
private struct RefreshButton: View {
    @Environment(\.ghafSwitchTap) private var passive
    let kind: String
    let tile: GhafTile
    let snapshot: GhafWidgetSnapshot?
    var body: some View {
        // In "switch view" mode the whole widget is the button, and buttons cannot nest.
        if !passive {
            Button(intent: GhafRefreshWidgetIntent(kind: kind)) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(tile.foreground)
                    .background(tile.foreground.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text(snapshot, "Refresh", "تحديث"))
        }
    }
}

private struct SymbolBadge: View {
    let symbol: String
    let tile: GhafTile
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(tile.background)
            .frame(width: size, height: size)
            .background(tile.foreground, in: Circle())
            .accessibilityHidden(true)
    }
}

private func dayText(_ date: Date, _ s: GhafWidgetSnapshot) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return date.formatted(.dateTime.hour().minute().locale(s.locale)) }
    return date.formatted(.dateTime.day().month(.abbreviated).locale(s.locale))
}

/// "Today", "Tomorrow", "In 5 days", or "Due" when the date has passed without a confirmed payment.
private func dueText(_ date: Date, now: Date, _ s: GhafWidgetSnapshot) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    switch days {
    case ..<0: return text(s, "Due", "مستحق")
    case 0: return text(s, "Today", "اليوم")
    case 1: return text(s, "Tomorrow", "غداً")
    default: return text(s, "In \(days) days", "بعد \(days.formatted(.number.locale(s.locale))) أيام")
    }
}

private extension View {
    func ghafLayout(_ s: GhafWidgetSnapshot?) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, s?.arabic == true ? .rightToLeft : .leftToRight)
    }
}

// MARK: 1. Latest transaction

struct GhafRecentWidget: Widget {
    static let kind = "GhafRecent"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafRecentConfig.self, provider: GhafConfigProvider<GhafRecentConfig>(kind: Self.kind)) { entry in
            GhafRecentView(entry: entry).ghafTap(GhafRecentWidget.kind, entry.config.onTap).fontDesign(entry.config.font.design).containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.config.glass) }
        }
        .configurationDisplayName("Latest transaction")
        .description("The last purchase or deposit Ghaf recorded, from a bank message, a shortcut or by hand.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct GhafRecentView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafConfigEntry<GhafRecentConfig>

    var body: some View {
        guard let s = entry.snapshot else { return AnyView(OpenGhaf(ink: family.isAccessory ? .primary : GhafTile(entry.config.style, nil).foreground)) }
        guard let latest = s.recent else {
            return AnyView(Text(text(s, "No transactions yet", "لا عمليات بعد")).font(.caption.weight(.semibold))
                .foregroundStyle(family.isAccessory ? .primary : GhafTile(entry.config.style, s).dim))
        }
        let tile = GhafTile(entry.config.style, s)
        let flipped = entry.config.onTap == .switchView && GhafNextViewIntent.count(GhafRecentWidget.kind) % 2 == 1
        // Tapping flips between the latest transaction and what has been spent today.
        let r = flipped
            ? GhafWidgetSnapshot.Recent(merchant: nil, category: text(s, "Spent today", "صرف اليوم"), symbol: "calendar", amount: s.spentToday,
                                        currency: s.currency, date: s.updated, isCredit: false, account: nil, bank: nil, needsReview: false)
            : latest
        let amount = (r.isCredit ? "+" : "") + (s.hidden ? "✦✦✦" : r.amount.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: r.currency))).locale(s.locale)))
        let detail = [entry.config.showMerchant ? r.merchant : nil, entry.config.showAccount ? r.account : nil]
            .compactMap { $0 }.joined(separator: " · ")
        let label = text(s, "Latest: \(r.category), \(r.currency) \(amount)", "آخر عملية: \(r.category)، \(amount) \(r.currency)")

        switch family {
        case .accessoryInline:
            return AnyView(Label("\(r.currency) \(amount) · \(r.category)", systemImage: r.symbol).privacySensitive())
        case .accessoryRectangular:
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: r.symbol).font(.system(size: 10, weight: .bold))
                    Caption(value: r.category)
                }
                .opacity(0.75)
                Text("\(r.currency) \(amount)").font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1).privacySensitive()
                if !detail.isEmpty { Text(detail).font(.caption2).lineLimit(1).opacity(0.75).privacySensitive() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel(label))
        case .systemMedium:
            return AnyView(HStack(alignment: .top, spacing: 14) {
                SymbolBadge(symbol: r.symbol, tile: tile, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Caption(value: text(s, "Latest · ", "آخر عملية · ") + dayText(r.date, s)).foregroundStyle(tile.dim)
                    Text(r.category).font(.system(size: 24, weight: .heavy)).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.6).privacySensitive()
                    if !detail.isEmpty { Text(detail).font(.system(size: 12, weight: .semibold)).foregroundStyle(tile.dim).lineLimit(1).privacySensitive() }
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(amount).font(.system(size: 34, weight: .heavy)).tracking(-1).lineLimit(1).minimumScaleFactor(0.5)
                            .contentTransition(.numericText()).privacySensitive()
                        Text(r.currency).font(.system(size: 13, weight: .bold)).foregroundStyle(tile.dim)
                        Spacer(minLength: 0)
                        reviewMark(r, s, tile)
                    }
                }
                RefreshButton(kind: GhafRecentWidget.kind, tile: tile, snapshot: s)
            }
            .foregroundStyle(tile.foreground)
            .ghafLayout(s)
            .accessibilityElement(children: .contain).accessibilityLabel(label))
        default:
            return AnyView(VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    SymbolBadge(symbol: r.symbol, tile: tile, size: 34)
                    Spacer(minLength: 0)
                    RefreshButton(kind: GhafRecentWidget.kind, tile: tile, snapshot: s)
                }
                Spacer(minLength: 0)
                Text(r.category).font(.system(size: 17, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6).privacySensitive()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(amount).font(.system(size: 30, weight: .heavy)).tracking(-1).lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText()).privacySensitive()
                    Text(r.currency).font(.system(size: 11, weight: .bold)).foregroundStyle(tile.dim)
                }
                Text(([entry.config.showMerchant ? r.merchant : nil, dayText(r.date, s)].compactMap { $0 }).joined(separator: " · "))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(tile.dim).lineLimit(1).privacySensitive()
            }
            .foregroundStyle(tile.foreground)
            .ghafLayout(s)
            .accessibilityElement(children: .contain).accessibilityLabel(label))
        }
    }

    @ViewBuilder private func reviewMark(_ r: GhafWidgetSnapshot.Recent, _ s: GhafWidgetSnapshot, _ tile: GhafTile) -> some View {
        if r.needsReview {
            Text(text(s, "Needs review", "تحتاج مراجعة"))
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(tile.foreground.opacity(0.14), in: Capsule())
        }
    }
}

// MARK: 2. Spending (Day / Week / Month)

struct GhafSpendingWidget: Widget {
    static let kind = "GhafSpending"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafSpendingConfig.self, provider: GhafConfigProvider<GhafSpendingConfig>(kind: Self.kind)) { entry in
            GhafSpendingView(entry: entry).ghafTap(GhafSpendingWidget.kind, entry.config.onTap).fontDesign(entry.config.font.design).containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.config.glass) }
        }
        .configurationDisplayName("Spending")
        .description("Today, this week or this month. Tap Day, Week or Month to switch.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GhafSpendingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafConfigEntry<GhafSpendingConfig>

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        guard let s = entry.snapshot else { return AnyView(OpenGhaf(ink: tile.foreground)) }
        let selected = ghafSelectedPeriod(GhafSpendingWidget.kind, configured: entry.config.period, tap: entry.config.onTap)
        let switcher = PeriodSwitch(kind: GhafSpendingWidget.kind, configured: entry.config.period, selected: selected, tile: tile, snapshot: s)
        guard let p = s.shown(selected, at: entry.date) else {
            return AnyView(VStack { Spacer(); Text(text(s, "Open Ghaf to load this period", "افتح غاف لتحميل هذه الفترة")).font(.caption.weight(.semibold)); Spacer(); switcher }
                .foregroundStyle(tile.foreground).ghafLayout(s))
        }
        let compare: String? = entry.config.compare ? p.previous.map {
            text(s, "\(s.currency) \(s.whole($0)) \(lastPeriodName(selected, s))", "\(lastPeriodName(selected, s)) \(s.whole($0)) \(s.currency)")
        } : nil
        let headline = VStack(alignment: .leading, spacing: 3) {
            Caption(value: text(s, "Spent · ", "صرفت · ") + periodName(selected, s)).foregroundStyle(tile.dim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(s.whole(p.spent)).font(.system(size: family == .systemSmall ? 34 : 38, weight: .heavy)).tracking(-1.2)
                    .lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText()).privacySensitive()
                Text(s.currency).font(.system(size: 12, weight: .bold)).foregroundStyle(tile.dim)
            }
            if let compare {
                Text(compare).font(.system(size: 11, weight: .bold)).foregroundStyle(tile.highlight == tile.foreground ? tile.dim : tile.highlight)
                    .lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
            }
        }
        .accessibilityElement(children: .combine)

        if family == .systemMedium {
            return AnyView(HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    headline
                    Spacer(minLength: 0)
                    Text(text(s, "\(p.count) purchases", "\(p.count.formatted(.number.locale(s.locale))) عمليات شراء"))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(tile.dim)
                }
                VStack(spacing: 10) {
                    WeekBars(days: p.bars, base: tile.foreground.opacity(0.14), highlight: tile.highlight, current: p.current, height: 58)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    switcher
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(tile.foreground).ghafLayout(s))
        }
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            headline
            Spacer(minLength: 6)
            WeekBars(days: p.bars, base: tile.foreground.opacity(0.14), highlight: tile.highlight, current: p.current, height: 18)
            Spacer(minLength: 6)
            switcher
        }
        .foregroundStyle(tile.foreground).ghafLayout(s))
    }
}

// MARK: 3. Budget left

struct GhafBudgetWidget: Widget {
    static let kind = "GhafBudget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafBudgetConfig.self, provider: GhafConfigProvider<GhafBudgetConfig>(kind: Self.kind)) { entry in
            GhafBudgetView(entry: entry).ghafTap(GhafBudgetWidget.kind, entry.config.onTap).fontDesign(entry.config.font.design).containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.config.glass) }
        }
        .configurationDisplayName("Budget")
        .description("How much of your budget is left, from your Budget settings in Ghaf.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct GhafBudgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafConfigEntry<GhafBudgetConfig>

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        guard let s = entry.snapshot else { return AnyView(OpenGhaf(ink: family.isAccessory ? .primary : tile.foreground)) }
        guard let b = s.budget, b.limit > 0 else {
            if family == .accessoryCircular {
                return AnyView(ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "chart.pie").font(.system(size: 20, weight: .semibold))
                }
                .accessibilityLabel(text(s, "Set a budget in Ghaf", "حدد ميزانية في غاف")))
            }
            return AnyView(VStack(spacing: 4) {
                Image(systemName: "chart.pie").font(.system(size: 18, weight: .semibold))
                Text(text(s, "Set a budget in Ghaf", "حدد ميزانية في غاف")).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(family.isAccessory ? .primary : tile.foreground))
        }
        // After the budget period ends nothing has been recorded since the app last wrote (it rewrites on every transaction).
        let spent = entry.date >= b.end ? 0 : b.spent
        let left = b.limit - spent
        let usedShare = NSDecimalNumber(decimal: spent / b.limit).doubleValue
        let flipped = entry.config.onTap == .switchView && GhafNextViewIntent.count(GhafBudgetWidget.kind) % 2 == 1
        let showLeft = (entry.config.display == .left) != flipped
        let share = showLeft ? max(0, 1 - usedShare) : usedShare
        let percent = share.formatted(.percent.precision(.fractionLength(0)).locale(s.locale))
        let caption = showLeft ? text(s, "Budget left", "المتبقي من الميزانية") : text(s, "Budget used", "المستخدم من الميزانية")
        let footer = left < 0
            ? text(s, "Over by \(s.currency) \(s.whole(-left))", "تجاوزت بـ \(s.whole(-left)) \(s.currency)")
            : text(s, "\(s.currency) \(s.whole(showLeft ? left : spent)) of \(s.whole(b.limit))", "\(s.whole(showLeft ? left : spent)) من \(s.whole(b.limit)) \(s.currency)")
        let spoken = text(s, "\(b.title): \(percent) \(showLeft ? "left" : "used")", "\(b.title): \(percent)")

        switch family {
        case .accessoryCircular:
            return AnyView(Gauge(value: min(max(share, 0), 1)) { Text(s.currency) } currentValueLabel: { Text(percent).minimumScaleFactor(0.5) }
                .gaugeStyle(.accessoryCircularCapacity)
                .accessibilityLabel(spoken))
        case .accessoryRectangular:
            return AnyView(VStack(alignment: .leading, spacing: 2) {
                Caption(value: caption).opacity(0.75)
                Text(percent).font(.system(size: 20, weight: .bold))
                Gauge(value: min(max(share, 0), 1)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                Text(footer).font(.caption2).lineLimit(1).privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken))
        default:
            let header = HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Caption(value: caption).foregroundStyle(tile.dim)
                    Text(b.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(tile.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                RefreshButton(kind: GhafBudgetWidget.kind, tile: tile, snapshot: s)
            }
            let big = Text(left < 0 && showLeft ? "0%" : percent)
                .font(.system(size: family == .systemSmall ? 44 : 48, weight: .heavy)).tracking(-1.5)
                .lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText())
            let bars = entry.config.showWeek ? s.lastSevenDays(at: entry.date).map {
                WeekBars(days: $0, base: tile.foreground.opacity(0.18), highlight: tile.foreground)
            } : nil
            let foot = Text(footer).font(.system(size: 11, weight: .bold)).foregroundStyle(tile.dim).lineLimit(1).minimumScaleFactor(0.7).privacySensitive()

            if family == .systemMedium {
                return AnyView(VStack(alignment: .leading, spacing: 6) {
                    header
                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) { big; foot }
                        if let bars { bars.frame(maxWidth: .infinity) }
                    }
                    Spacer(minLength: 0)
                    ProgressView(value: min(max(usedShare, 0), 1))
                        .progressViewStyle(.linear).tint(tile.foreground)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(tile.foreground).ghafLayout(s)
                .accessibilityElement(children: .contain).accessibilityLabel(spoken))
            }
            return AnyView(VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                big
                if let bars { bars }
                foot
            }
            .foregroundStyle(tile.foreground).ghafLayout(s)
            .accessibilityElement(children: .contain).accessibilityLabel(spoken))
        }
    }
}

// MARK: 4. Where it went (top categories)

struct GhafCategoriesWidget: Widget {
    static let kind = "GhafCategories"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafCategoriesConfig.self, provider: GhafConfigProvider<GhafCategoriesConfig>(kind: Self.kind)) { entry in
            GhafCategoriesView(entry: entry).ghafTap(GhafCategoriesWidget.kind, entry.config.onTap).fontDesign(entry.config.font.design).containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.config.glass) }
        }
        .configurationDisplayName("Where it went")
        .description("Your top spending categories. Tap Day, Week or Month to switch.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct GhafCategoriesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafConfigEntry<GhafCategoriesConfig>

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        guard let s = entry.snapshot else { return AnyView(OpenGhaf(ink: tile.foreground)) }
        let selected = ghafSelectedPeriod(GhafCategoriesWidget.kind, configured: entry.config.period, tap: entry.config.onTap)
        let p = s.shown(selected, at: entry.date)
        let rows = Array((p?.categories ?? []).prefix(family == .systemLarge ? 5 : 3))
        let total = max(rows.reduce(Decimal.zero) { $0 + $1.amount }, 1)
        let large = family == .systemLarge

        return AnyView(VStack(alignment: .leading, spacing: large ? 12 : 7) {
            HStack(alignment: .firstTextBaseline) {
                Caption(value: text(s, "Where it went · ", "أين ذهبت · ") + periodName(selected, s)).foregroundStyle(tile.dim)
                Spacer(minLength: 4)
                if let p { Text("\(s.currency) \(s.whole(p.spent))").font(.system(size: 12, weight: .bold)).privacySensitive() }
            }
            if rows.isEmpty {
                Spacer(minLength: 0)
                Text(p == nil ? text(s, "Open Ghaf to load this period", "افتح غاف لتحميل هذه الفترة")
                              : text(s, "No spending in this period yet", "لا صرف في هذه الفترة بعد"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(tile.dim)
                Spacer(minLength: 0)
            } else {
                // One bar split by category, as in the Today spending artboard.
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, c in
                            Capsule().fill(tile.palette[i % tile.palette.count])
                                .frame(width: max(4, (geo.size.width - CGFloat(rows.count - 1) * 3) * CGFloat(NSDecimalNumber(decimal: c.amount / total).doubleValue)))
                        }
                    }
                }
                .frame(height: large ? 10 : 8)
                .accessibilityHidden(true)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, c in
                    HStack(spacing: 8) {
                        if large {
                            // Custom categories have no built-in symbol; a tag keeps every row the same shape.
                            Image(systemName: c.symbol ?? "tag.fill").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                                .foregroundStyle(tile.background).background(tile.palette[i % tile.palette.count], in: Circle())
                        } else {
                            RoundedRectangle(cornerRadius: 2).fill(tile.palette[i % tile.palette.count]).frame(width: 4, height: 13)
                        }
                        Text(c.name).font(.system(size: large ? 15 : 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if entry.config.showAmounts {
                            Text(s.hidden ? "✦✦✦" : c.amount.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: s.currency))).locale(s.locale)))
                                .font(.system(size: large ? 14 : 12, weight: .semibold, design: .monospaced)).privacySensitive()
                        } else {
                            Text((NSDecimalNumber(decimal: c.amount / total).doubleValue).formatted(.percent.precision(.fractionLength(0)).locale(s.locale)))
                                .font(.system(size: large ? 14 : 12, weight: .semibold, design: .monospaced))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            PeriodSwitch(kind: GhafCategoriesWidget.kind, configured: entry.config.period, selected: selected, tile: tile, snapshot: s)
        }
        .foregroundStyle(tile.foreground).ghafLayout(s))
    }
}

// MARK: 5. Upcoming payments (subscriptions)

struct GhafBillsWidget: Widget {
    static let kind = "GhafBills"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafBillsConfig.self, provider: GhafConfigProvider<GhafBillsConfig>(kind: Self.kind)) { entry in
            GhafBillsView(entry: entry).ghafTap(GhafBillsWidget.kind, entry.config.onTap).fontDesign(entry.config.font.design).containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.config.glass) }
        }
        .configurationDisplayName("Upcoming payments")
        .description("Subscriptions due soon. A reminder is not a payment: Ghaf records it when the charge arrives.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct GhafBillsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafConfigEntry<GhafBillsConfig>

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        guard let s = entry.snapshot else { return AnyView(OpenGhaf(ink: family.isAccessory ? .primary : tile.foreground)) }
        let calendar = Calendar.current
        let window = ghafStepped([GhafBillWindow.week, .fortnight, .month], start: entry.config.window, kind: GhafBillsWidget.kind, tap: entry.config.onTap)
        let limit = calendar.date(byAdding: .day, value: window.rawValue, to: calendar.startOfDay(for: entry.date)) ?? entry.date
        let bills = (s.upcoming ?? []).filter { $0.date < limit }
        // A total only when every bill shares one currency: unlike currencies are never added.
        let currencies = Set(bills.map(\.currency))
        let total: String? = entry.config.showTotal && currencies.count == 1
            ? "\(bills[0].currency) \(s.whole(bills.reduce(Decimal.zero) { $0 + $1.amount }))" : nil
        let windowText = text(s, "Next \(window.rawValue) days", "خلال \(window.rawValue.formatted(.number.locale(s.locale))) يوماً")

        guard let next = bills.first else {
            let empty = text(s, "Nothing due soon", "لا مدفوعات قريبة")
            if family.isAccessory { return AnyView(Text(empty).font(.caption.weight(.semibold))) }
            return AnyView(VStack(alignment: .leading) {
                HStack { Caption(value: windowText).foregroundStyle(tile.dim); Spacer(); RefreshButton(kind: GhafBillsWidget.kind, tile: tile, snapshot: s) }
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .bold))
                Text(empty).font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(tile.foreground).ghafLayout(s))
        }
        let amount = { (b: GhafWidgetSnapshot.Bill) in s.hidden ? "✦✦✦" : b.amount.formatted(.number.precision(.fractionLength(GhafCurrencyDigits.fractionDigits(for: b.currency))).locale(s.locale)) }

        switch family {
        case .accessoryRectangular:
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                Caption(value: dueText(next.date, now: entry.date, s)).opacity(0.75)
                Text(next.name).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text("\(next.currency) \(amount(next))" + (bills.count > 1 ? text(s, " · +\(bills.count - 1) more", " · +\(bills.count - 1)") : ""))
                    .font(.caption2).lineLimit(1).privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading))
        case .systemMedium:
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Caption(value: text(s, "Upcoming · ", "القادمة · ") + windowText).foregroundStyle(tile.dim)
                    Spacer(minLength: 4)
                    if let total { Text(total).font(.system(size: 12, weight: .bold)).privacySensitive() }
                    RefreshButton(kind: GhafBillsWidget.kind, tile: tile, snapshot: s)
                }
                ForEach(Array(bills.prefix(3).enumerated()), id: \.offset) { _, b in
                    HStack(spacing: 10) {
                        SymbolBadge(symbol: b.symbol, tile: tile, size: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(b.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                            Text(dueText(b.date, now: entry.date, s)).font(.system(size: 10, weight: .semibold)).foregroundStyle(tile.dim)
                        }
                        Spacer(minLength: 4)
                        Text("\(b.currency) \(amount(b))").font(.system(size: 12, weight: .semibold, design: .monospaced)).privacySensitive()
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(tile.foreground).ghafLayout(s))
        default:
            return AnyView(VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    SymbolBadge(symbol: next.symbol, tile: tile, size: 34)
                    Spacer(minLength: 0)
                    RefreshButton(kind: GhafBillsWidget.kind, tile: tile, snapshot: s)
                }
                Spacer(minLength: 0)
                Caption(value: dueText(next.date, now: entry.date, s)).foregroundStyle(tile.dim)
                Text(next.name).font(.system(size: 17, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(amount(next)).font(.system(size: 26, weight: .heavy)).tracking(-0.8).lineLimit(1).minimumScaleFactor(0.5).privacySensitive()
                    Text(next.currency).font(.system(size: 11, weight: .bold)).foregroundStyle(tile.dim)
                }
                if bills.count > 1 {
                    Text(text(s, "+\(bills.count - 1) more", "+\((bills.count - 1).formatted(.number.locale(s.locale))) أخرى") + (total.map { " · " + $0 } ?? ""))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(tile.dim).lineLimit(1).privacySensitive()
                }
            }
            .foregroundStyle(tile.foreground).ghafLayout(s))
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }
}
