import WidgetKit
import SwiftUI
import ActivityKit

@main
struct GhafWidgetBundle: WidgetBundle {
    var body: some Widget {
        GhafBalanceWidget()
        GhafTodayWidget()
        GhafPurchaseLiveActivity()
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
        completion(Timeline(entries: [GhafEntry(date: .now, snapshot: GhafWidgetSnapshot.load())], policy: .after(midnight)))
    }
}

extension GhafWidgetSnapshot {
    static let sample = GhafWidgetSnapshot(currency: "AED", balance: 12_450, spentToday: 86.5, spentThisMonth: 2_310,
                                           lastPurchase: .init(merchant: "Carrefour", amount: 45, currency: "AED", date: .now),
                                           hidden: false, arabic: false, updated: .now,
                                           todayCategories: [.init(name: "Groceries", amount: 45), .init(name: "Dining", amount: 28.5), .init(name: "Transport", amount: 13)],
                                           lastSevenDays: [120, 60, 210, 90, 40, 150, 86.5])
}

// Inspo palette: near-black tiles, lime highlight, a few category colours.
private let ink = Color(red: 0.05, green: 0.05, blue: 0.06)
private let lime = Color(red: 0.78, green: 0.96, blue: 0.38)
private let paper = Color(red: 0.95, green: 0.95, blue: 0.95)
private let categoryColors = [Color(red: 1, green: 0.35, blue: 0.12), lime, Color(red: 0.5, green: 0.7, blue: 1), Color(red: 0.72, green: 0.65, blue: 1)]

private func text(_ snapshot: GhafWidgetSnapshot?, _ en: String, _ ar: String) -> String { snapshot?.arabic == true ? ar : en }

/// Small caps caption used on every tile.
private struct Caption: View {
    let value: String
    var body: some View {
        Text(value.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6).lineLimit(1)
    }
}

/// Seven daily bars, today highlighted. Heights are relative to the week's largest day.
private struct WeekBars: View {
    let days: [Decimal]
    let base: Color
    let highlight: Color
    var body: some View {
        let peak = max(days.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == days.count - 1 ? highlight : base)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(NSDecimalNumber(decimal: value / peak).doubleValue) * 30))
            }
        }
        .frame(height: 30, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct OpenGhaf: View {
    let ink: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up.forward.app").font(.system(size: 18, weight: .semibold))
            Text("Open Ghaf to load your numbers").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(ink)
    }
}

// MARK: Balance widget

struct GhafBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafBalance", provider: GhafProvider()) { entry in
            GhafBalanceView(entry: entry).containerBackground(for: .widget) { ink }
        }
        .configurationDisplayName("Balance")
        .description("Your total balance and this week's spending.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct GhafBalanceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryInline:
                Text(s.balance.map { s.money($0) } ?? text(s, "Open Ghaf", "افتح غاف"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Caption(value: text(s, "Balance", "الرصيد"))
                    Text(s.balance.map { s.money($0) } ?? "—").font(.headline).minimumScaleFactor(0.6).privacySensitive()
                    Text(text(s, "Month ", "الشهر ") + s.money(s.spentThisMonth)).font(.caption2).privacySensitive()
                }
            default:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Caption(value: text(s, "Balance · ", "الرصيد · ") + s.currency).foregroundStyle(paper.opacity(0.55))
                        Spacer(minLength: 0)
                        if family == .systemSmall, let week = s.lastSevenDays { WeekBars(days: week, base: paper.opacity(0.14), highlight: lime) }
                        Text(s.balance.map { s.hidden ? "✦✦✦✦" : $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                            .font(.system(size: family == .systemSmall ? 30 : 36, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(paper)
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.numericText())
                            .privacySensitive()
                        Text(text(s, "Spent ", "صرفت ") + s.money(s.spentThisMonth) + text(s, " this month", " هذا الشهر"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(lime)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .privacySensitive()
                    }
                    if family == .systemMedium, let week = s.lastSevenDays {
                        VStack(alignment: .leading, spacing: 6) {
                            Caption(value: text(s, "Last 7 days", "آخر ٧ أيام")).foregroundStyle(paper.opacity(0.55))
                            Spacer(minLength: 0)
                            WeekBars(days: week, base: paper.opacity(0.14), highlight: lime).frame(height: 60)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
            }
        } else {
            OpenGhaf(ink: family == .systemSmall || family == .systemMedium ? paper : .primary)
        }
    }
}

// MARK: Today widget

struct GhafTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafToday", provider: GhafProvider()) { entry in
            GhafTodayView(entry: entry).containerBackground(for: .widget) { lime }
        }
        .configurationDisplayName("Today")
        .description("What you spent today, by category.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct GhafTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafEntry

    var body: some View {
        let s = entry.snapshot
        if family == .accessoryCircular {
            Gauge(value: 1) {
                Text(s?.currency ?? "AED")
            } currentValueLabel: {
                Text(s.map { $0.hidden ? "✦✦" : $0.spentToday.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else if let s {
            if family == .systemMedium { medium(s) } else { small(s) }
        } else {
            OpenGhaf(ink: ink)
        }
    }

    private func small(_ s: GhafWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(value: text(s, "Spent today", "صرف اليوم")).foregroundStyle(ink.opacity(0.6))
            Text(s.hidden ? "✦✦✦" : s.spentToday.formatted(.number.precision(.fractionLength(0))))
                .font(.system(size: 40, weight: .heavy)).tracking(-1.2)
                .foregroundStyle(ink).minimumScaleFactor(0.5).lineLimit(1)
                .privacySensitive()
            Spacer(minLength: 0)
            if let week = s.lastSevenDays { WeekBars(days: week, base: ink.opacity(0.18), highlight: ink) }
            Text(s.currency + text(s, " · this week", " · هذا الأسبوع")).font(.system(size: 11, weight: .bold)).foregroundStyle(ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
    }

    private func medium(_ s: GhafWidgetSnapshot) -> some View {
        let categories = s.todayCategories ?? []
        let total = max(categories.reduce(Decimal.zero) { $0 + $1.amount }, 1)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Caption(value: text(s, "Today spending", "صرف اليوم")).foregroundStyle(ink.opacity(0.6))
                Text(s.money(s.spentToday)).font(.system(size: 26, weight: .heavy)).tracking(-0.8)
                    .foregroundStyle(ink).minimumScaleFactor(0.5).lineLimit(1).privacySensitive()
                Spacer(minLength: 0)
                if let last = s.lastPurchase {
                    Text(text(s, "Last: ", "آخر عملية: ") + last.merchant).font(.system(size: 11, weight: .bold)).lineLimit(1)
                    Text(last.date, style: .relative).font(.system(size: 11)).foregroundStyle(ink.opacity(0.6))
                }
            }
            .foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 5) {
                if categories.isEmpty {
                    Text(text(s, "No spending yet today", "لا صرف اليوم بعد")).font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.6))
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(categories.enumerated()), id: \.offset) { i, c in
                                Capsule().fill(categoryColors[i % categoryColors.count] == lime ? ink : categoryColors[i % categoryColors.count])
                                    .frame(width: max(4, geo.size.width * CGFloat(NSDecimalNumber(decimal: c.amount / total).doubleValue) - 2))
                            }
                        }
                    }
                    .frame(height: 6)
                    ForEach(Array(categories.enumerated()), id: \.offset) { i, c in
                        HStack(spacing: 6) {
                            Circle().fill(categoryColors[i % categoryColors.count] == lime ? ink : categoryColors[i % categoryColors.count]).frame(width: 6, height: 6)
                            Text(c.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(s.hidden ? "✦✦" : c.amount.formatted(.number.precision(.fractionLength(2)))).privacySensitive()
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ink)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
    }
}

// MARK: Live Activity: a purchase just recorded

/// A small card glyph in the theme gradient, without a container (HIG: logo marks stand alone).
private struct GhafActivityMark: View {
    let attributes: GhafPurchaseAttributes
    var size: CGFloat = 16
    var body: some View {
        Image(systemName: "creditcard.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(LinearGradient(colors: [Color(ghafHex: attributes.glow), Color(ghafHex: attributes.accent)],
                                            startPoint: .top, endPoint: .bottom))
    }
}

private struct GhafCategoryBadge: View {
    let state: GhafPurchaseAttributes.ContentState
    let attributes: GhafPurchaseAttributes
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(ghafHex: attributes.glow), Color(ghafHex: attributes.accent)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
    }
}

struct GhafPurchaseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GhafPurchaseAttributes.self) { context in
            GhafPurchaseLockView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(Color(ghafHex: context.attributes.accent))
        } dynamicIsland: { context in
            let s = context.state
            let ar = context.attributes.arabic
            let tint = Color(ghafHex: context.attributes.glow)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GhafCategoryBadge(state: s, attributes: context.attributes, size: 46)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(s.merchant).font(.headline).lineLimit(1)
                        Text(s.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text((s.isCredit ? "+" : "−") + s.amount.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(s.isCredit ? .green : .white)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(s.currency).font(.caption2.weight(.bold)).foregroundStyle(tint)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        GhafActivityMark(attributes: context.attributes, size: 12)
                        if let name = s.accountName { Text(name).lineLimit(1) }
                        Spacer(minLength: 6)
                        if s.needsReview {
                            Text(ar ? "تحتاج مراجعة" : "Needs review")
                                .font(.caption.weight(.bold)).foregroundStyle(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.orange.opacity(0.18), in: Capsule())
                        } else if let balance = s.balance {
                            Text((ar ? "الرصيد " : "Balance ") + money(balance, s.currency)).privacySensitive()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            } compactLeading: {
                GhafActivityMark(attributes: context.attributes, size: 14)
            } compactTrailing: {
                Text((s.isCredit ? "+" : "−") + shortAmount(s))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(s.isCredit ? .green : tint)
            } minimal: {
                Text(shortAmount(s))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
            }
            .keylineTint(tint)
        }
    }
}

private func money(_ value: Decimal, _ currency: String) -> String {
    "\(currency) " + value.formatted(.number.precision(.fractionLength(2)))
}
private func amount(_ s: GhafPurchaseAttributes.ContentState) -> String { (s.isCredit ? "+" : "−") + money(s.amount, s.currency) }
/// Fits the 28 pt compact/minimal space: "45" or "1.2K".
private func shortAmount(_ s: GhafPurchaseAttributes.ContentState) -> String {
    s.amount >= 1000 ? (NSDecimalNumber(decimal: s.amount / 1000).doubleValue).formatted(.number.precision(.fractionLength(1))) + "K"
                     : s.amount.formatted(.number.precision(.fractionLength(0)))
}

struct GhafPurchaseLockView: View {
    let context: ActivityViewContext<GhafPurchaseAttributes>

    var body: some View {
        let s = context.state
        let ar = context.attributes.arabic
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                GhafCategoryBadge(state: s, attributes: context.attributes, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.merchant).font(.headline.weight(.bold)).lineLimit(1)
                    Text(s.isCredit ? (ar ? "وصلك مبلغ" : "Money received") : s.category)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text((s.isCredit ? "+" : "−") + s.amount.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(s.isCredit ? .green : .primary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(s.currency).font(.caption.weight(.bold)).foregroundStyle(Color(ghafHex: context.attributes.accent))
                }
            }
            HStack(spacing: 6) {
                GhafActivityMark(attributes: context.attributes, size: 11)
                Text(s.needsReview ? (ar ? "سُجّلت · تحتاج مراجعة في غاف" : "Recorded · needs a quick review in Ghaf")
                                   : (ar ? "سُجّلت في غاف" : "Recorded in Ghaf"))
                Spacer(minLength: 6)
                if let balance = s.balance, let name = s.accountName {
                    Text("\(name) · " + money(balance, s.currency)).lineLimit(1).privacySensitive()
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(s.needsReview ? .orange : .secondary)
        }
        .padding(14)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }
}
