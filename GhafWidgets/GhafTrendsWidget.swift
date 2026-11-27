import WidgetKit
import SwiftUI
import AppIntents

// Trends (1.21): a stock-ticker style read of how spending is moving. Everything comes from the same ledger
// snapshot the other widgets use; the line is spending per slice of the chosen period (hours, days or weeks).

/// A line with a soft fill, always drawn left to right like a price chart.
private struct GhafSparkline: View {
    let values: [Double]
    let line: Color
    let fill: Bool

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if fill, let first = pts.first, let last = pts.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [line.opacity(0.32), line.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(line, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(line).frame(width: 7, height: 7).position(last)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        // A single slice (or none) is drawn as a flat line so the chart never collapses.
        let v = values.count >= 2 ? values : [0, values.first ?? 0]
        let peak = max(v.max() ?? 0, 1)
        let inset: CGFloat = 5
        return v.enumerated().map { i, value in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(v.count - 1),
                    y: inset + (size.height - 2 * inset) * (1 - CGFloat(value / peak)))
        }
    }
}

struct GhafTrendsWidget: Widget {
    static let kind = "GhafTrends"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: GhafTrendsConfig.self, provider: GhafConfigProvider<GhafTrendsConfig>(kind: Self.kind)) { entry in
            GhafTrendsView(entry: entry).ghafTap(Self.kind, entry.config.onTap).fontDesign(entry.config.font.design(arabic: entry.snapshot?.arabic)).environment(\.locale, GhafLocale.locale(identifier: entry.snapshot?.arabic == true ? "ar_AE" : "en_AE"))
                .containerBackground(for: .widget) { GhafWidgetBackground(tile: GhafTile(entry.config.style, entry.snapshot), enabled: entry.config.glass) }
                .modifier(GhafWidgetProLock(required: true, isArabic: entry.snapshot?.arabic) {
                    GhafTrendsView(entry: .init(date: entry.date, snapshot: .proPreview(arabic: entry.snapshot?.arabic), config: entry.config))
                })
        }
        .configurationDisplayName("Trends")
        .description("How your spending is moving, like a stock chart. Tap to switch between 1D, 1W and 1M.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct GhafTrendsView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var galleryFamily: WidgetFamily? = nil
    private var family: WidgetFamily { galleryFamily ?? systemFamily }
    let entry: GhafConfigEntry<GhafTrendsConfig>

    var body: some View {
        let tile = GhafTile(entry.config.style, entry.snapshot)
        guard let s = entry.snapshot else { return AnyView(OpenGhaf(ink: family.isAccessory ? .primary : tile.foreground)) }
        let selected = ghafSelectedPeriod(GhafTrendsWidget.kind, configured: entry.config.period, tap: entry.config.onTap)
        guard let p = s.shown(selected, at: entry.date) else {
            return AnyView(Text(text(s, "Open Ghaf to load this period", "افتح غاف لتحميل هذه الفترة")).font(.caption.weight(.semibold))
                .foregroundStyle(family.isAccessory ? .primary : tile.foreground))
        }

        // Only the slices that have happened: the rest of the week or month would drag the line to zero.
        let upTo = min(p.bars.count, (p.current ?? p.bars.count - 1) + 1)
        let values = p.bars.prefix(max(upTo, 1)).map { NSDecimalNumber(decimal: $0).doubleValue }

        // Spending going up is the bad direction, so up is red and down is green; the arrow and sign carry it too.
        let change: Double? = p.previous.flatMap { $0 > 0 ? NSDecimalNumber(decimal: (p.spent - $0) / $0).doubleValue : nil }
        let up = (change ?? 0) > 0
        let good = tile.isDark ? Color(ghafHex: 0x30D158) : Color(ghafHex: 0x1F8A3D)
        let bad = tile.isDark ? Color(ghafHex: 0xFF453A) : Color(ghafHex: 0xC8201A)
        let move = change == nil ? tile.dim : (up ? bad : good)
        let lineColor = change == nil ? tile.highlight : move

        let amount = Text(s.whole(p.spent)).tracking(-1).lineLimit(1).minimumScaleFactor(0.5)
            .contentTransition(.numericText()).privacySensitive()
        let pill: AnyView? = (entry.config.showChange ? change : nil).map { c in
            AnyView(HStack(spacing: 3) {
                Image(systemName: c > 0 ? "arrow.up.right" : c < 0 ? "arrow.down.right" : "equal")
                Text(abs(c).formatted(.percent.precision(.fractionLength(0)).locale(s.locale)))
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(move)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(move.opacity(0.16), in: Capsule())
            .accessibilityLabel(text(s, "\(c > 0 ? "Up" : "Down") \(Int((abs(c) * 100).rounded())) percent vs \(lastPeriodName(selected, s))",
                                     "\(c > 0 ? "أعلى" : "أقل") بنسبة \(Int((abs(c) * 100).rounded())) بالمئة عن \(lastPeriodName(selected, s))")))
        }
        let title = text(s, "Spending", "المصروف")
        let spoken = text(s, "Spending \(periodName(selected, s)): \(s.currency) \(s.whole(p.spent))",
                          "الصرف \(periodName(selected, s)): \(s.whole(p.spent)) \(s.currency)")

        switch family {
        case .accessoryRectangular:
            return AnyView(HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Caption(value: title + " · " + periodName(selected, s)).opacity(0.75)
                    amount.font(ghafNumberFont(20, weight: .bold))
                }
                GhafSparkline(values: values, line: .primary, fill: false).frame(width: 44, height: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken))
        case .systemMedium:
            return AnyView(HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Caption(value: title).foregroundStyle(tile.dim)
                    Text(periodName(selected, s)).font(.system(size: 11, weight: .semibold)).foregroundStyle(tile.dim)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        amount.font(ghafNumberFont(32, weight: .bold))
                        Text(s.currency).font(.system(size: 12, weight: .bold)).foregroundStyle(tile.dim)
                    }
                    if let pill { pill }
                }
                VStack(spacing: 8) {
                    GhafSparkline(values: values, line: lineColor, fill: entry.config.showFill).frame(maxHeight: .infinity)
                    PeriodSwitch(short: true, kind: GhafTrendsWidget.kind, configured: entry.config.period, selected: selected, tile: tile, snapshot: s)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(tile.foreground).ghafTrendsLayout(s)
            .accessibilityElement(children: .contain).accessibilityLabel(spoken))
        default:
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Caption(value: title).foregroundStyle(tile.dim)
                        Text(periodName(selected, s)).font(.system(size: 10, weight: .semibold)).foregroundStyle(tile.dim)
                    }
                    Spacer(minLength: 4)
                    if let pill { pill }
                }
                GhafSparkline(values: values, line: lineColor, fill: entry.config.showFill).frame(maxHeight: .infinity).padding(.vertical, 4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    amount.font(ghafNumberFont(26, weight: .bold))
                    Text(s.currency).font(.system(size: 10, weight: .bold)).foregroundStyle(tile.dim)
                }
            }
            .foregroundStyle(tile.foreground).ghafTrendsLayout(s)
            .accessibilityElement(children: .contain).accessibilityLabel(spoken))
        }
    }
}

private extension View {
    func ghafTrendsLayout(_ s: GhafWidgetSnapshot?) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, s?.arabic == true ? .rightToLeft : .leftToRight)
    }
}
