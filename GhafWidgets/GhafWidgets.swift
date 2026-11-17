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
                                           hidden: false, arabic: false, updated: .now)
}

private let ghafGreen = Color(red: 0.11, green: 0.42, blue: 0.40)
private let ghafSand = Color(red: 0.55, green: 0.36, blue: 0.16)

/// The Ghaf tree drawn without a container, as the HIG asks for logo marks.
struct GhafWidgetTree: View {
    var body: some View {
        Image(systemName: "tree.fill").font(.system(size: 13, weight: .bold))
    }
}

private func text(_ snapshot: GhafWidgetSnapshot?, _ en: String, _ ar: String) -> String { snapshot?.arabic == true ? ar : en }

// MARK: Balance widget

struct GhafBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafBalance", provider: GhafProvider()) { entry in
            GhafBalanceView(entry: entry).containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Balance")
        .description("Your total balance and this month's spending.")
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
                    Label(text(s, "Balance", "الرصيد"), systemImage: "tree.fill").font(.caption2.weight(.semibold))
                    Text(s.balance.map { s.money($0) } ?? "—").font(.headline).minimumScaleFactor(0.6).privacySensitive()
                    Text(text(s, "Month ", "الشهر ") + s.money(s.spentThisMonth)).font(.caption2).privacySensitive()
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack { GhafWidgetTree().foregroundStyle(ghafGreen); Spacer()
                        Text(text(s, "Total", "الإجمالي")).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    Text(s.balance.map { s.money($0) } ?? "—")
                        .font(.system(size: family == .systemSmall ? 22 : 30, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .contentTransition(.numericText())
                        .privacySensitive()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right").foregroundStyle(.red)
                        Text(s.money(s.spentThisMonth)).privacySensitive()
                        Text(text(s, "this month", "هذا الشهر")).foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .environment(\.layoutDirection, s.arabic ? .rightToLeft : .leftToRight)
            }
        } else {
            VStack(spacing: 6) {
                GhafWidgetTree().foregroundStyle(ghafGreen)
                Text("Open Ghaf to load your balance").font(.caption).multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: Today widget

struct GhafTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GhafToday", provider: GhafProvider()) { entry in
            GhafTodayView(entry: entry).containerBackground(for: .widget) {
                LinearGradient(colors: [ghafGreen, ghafGreen.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            }
        }
        .configurationDisplayName("Today")
        .description("What you spent today and your last purchase.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct GhafTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GhafEntry

    var body: some View {
        let s = entry.snapshot
        if family == .accessoryCircular {
            VStack(spacing: 0) {
                Image(systemName: "tree.fill").font(.system(size: 11, weight: .bold))
                Text(s.map { $0.hidden ? "✦✦" : $0.spentToday.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5)
                Text(s?.currency ?? "AED").font(.system(size: 8, weight: .semibold))
            }
        } else {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text(s, "Today", "اليوم")).font(.caption.weight(.bold)).opacity(0.75)
                    Text(s.map { $0.money($0.spentToday) } ?? "—")
                        .font(.system(size: 24, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        .privacySensitive()
                    Spacer(minLength: 0)
                    if let last = s?.lastPurchase, family == .systemSmall {
                        Text(last.merchant).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(last.date, style: .relative).font(.caption2).opacity(0.7)
                    }
                }
                if family == .systemMedium, let last = s?.lastPurchase, let s {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text(s, "Last purchase", "آخر عملية")).font(.caption.weight(.bold)).opacity(0.75)
                        Text(last.merchant).font(.headline).lineLimit(1)
                        Text(s.money(last.amount, currency: last.currency)).font(.subheadline.weight(.semibold)).privacySensitive()
                        Text(last.date, style: .relative).font(.caption2).opacity(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.white.opacity(0.14), in: ContainerRelativeShape())
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, s?.arabic == true ? .rightToLeft : .leftToRight)
        }
    }
}

// MARK: Live Activity: a purchase just recorded

struct GhafPurchaseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GhafPurchaseAttributes.self) { context in
            GhafPurchaseLockView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(ghafGreen)
        } dynamicIsland: { context in
            let s = context.state
            let ar = context.attributes.arabic
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(s.merchant).lineLimit(1) } icon: { Image(systemName: "tree.fill").foregroundStyle(.green) }
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(amount(s)).font(.headline.weight(.heavy)).foregroundStyle(s.isCredit ? .green : .white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let name = s.accountName {
                            Text(name).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let balance = s.balance {
                            Text((ar ? "الرصيد " : "Balance ") + money(balance, s.currency)).privacySensitive()
                        }
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "tree.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text(shortAmount(s)).font(.caption.weight(.heavy)).foregroundStyle(s.isCredit ? .green : .white)
            } minimal: {
                Text(shortAmount(s)).font(.system(size: 11, weight: .heavy)).minimumScaleFactor(0.5)
            }
            .keylineTint(.green)
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
        HStack(spacing: 14) {
            Image(systemName: s.isCredit ? "arrow.down.circle.fill" : "bag.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(ghafGreen, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(s.isCredit ? (ar ? "وصلك مبلغ" : "Money received") : (ar ? "تم تسجيل عملية" : "Purchase recorded"))
                    .font(.headline.weight(.bold))
                HStack(spacing: 6) {
                    Text(amount(s)).font(.subheadline.weight(.semibold))
                    Text("·").foregroundStyle(.secondary)
                    Text(s.merchant).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let balance = s.balance, let name = s.accountName {
                    Text((ar ? "رصيد \(name): " : "\(name) balance: ") + money(balance, s.currency))
                        .font(.caption).foregroundStyle(.secondary).privacySensitive()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: s.needsReview ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(s.needsReview ? .orange : ghafGreen)
        }
        .padding(14)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }
}
