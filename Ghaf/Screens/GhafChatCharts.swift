import SwiftUI
import Charts

/// A chart Ghaf attaches to an answer. Values come from the ledger, never from the language model.
struct GhafChatChart {
    enum Style: String { case bar, donut, rose, line }
    enum Kind: String { case categories, week, compare, trend }

    struct Point: Identifiable { let id = UUID(); let label: String; let value: Double; var highlight = false }
    let kind: Kind
    let style: Style
    let title: String
    let currency: String
    let points: [Point]

    func restyled(_ style: Style) -> GhafChatChart {
        GhafChatChart(kind: kind, style: style, title: title, currency: currency, points: points)
    }
}

/// Picks the chart a question asks for and builds it from the user's transactions.
@MainActor
enum GhafChatChartBuilder {
    private static func has(_ q: String, _ words: [String]) -> Bool { words.contains { q.contains($0) } }

    /// The chart style named in the message, if any ("as a pie", "line chart", "دائري").
    static func style(in question: String) -> GhafChatChart.Style? {
        let q = question.lowercased()
        if has(q, ["rose", "petal", "flower", "polar", "radial", "وردة", "زهرة", "بتلات"]) { return .rose }
        if has(q, ["pie", "donut", "doughnut", "share", "percent", "دائري", "دائرة", "نسبة", "حصة"]) { return .donut }
        if has(q, ["line", "trend", "over time", "خط", "اتجاه", "تطور"]) { return .line }
        if has(q, ["bar", "column", "أعمدة", "عمود"]) { return .bar }
        return nil
    }

    /// True when the message only asks to redraw the last chart differently ("show it as a donut").
    static func isRestyleOnly(_ question: String) -> Bool {
        let q = question.lowercased()
        return style(in: q) != nil && !has(q, ["week", "month", "today", "categor", "compare", "spend", "أسبوع", "شهر", "فئة", "قارن", "صرف", "اليوم"])
    }

    static func chart(for question: String, transactions: [GhafTransaction], currency: String, languageCode: String) -> GhafChatChart? {
        let q = question.lowercased()
        let ar = languageCode == "ar"
        let calendar = GhafCalendar.current
        let spending = transactions.filter { $0.currency == currency && $0.isExpense }
        func total(_ interval: DateInterval?) -> Double {
            guard let interval else { return 0 }
            return NSDecimalNumber(decimal: spending.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.spendingAmount }).doubleValue
        }
        let requested = style(in: q)

        if has(q, ["compare", " vs", "last month", "more than", "قارن", "الشهر الماضي", "أكثر من"]) {
            let this = calendar.dateInterval(of: .month, for: .now)
            let last = calendar.date(byAdding: .month, value: -1, to: .now).flatMap { calendar.dateInterval(of: .month, for: $0) }
            return GhafChatChart(kind: .compare, style: requested ?? .bar,
                                 title: ar ? "هذا الشهر مقابل الماضي" : "This month vs last month", currency: currency, points: [
                .init(label: ar ? "الماضي" : "Last", value: total(last)),
                .init(label: ar ? "هذا" : "This", value: total(this), highlight: true)
            ])
        }
        if requested == .line || has(q, ["trend", "over time", "this month daily", "تطور", "اتجاه"]) {
            // Running total for each day of the month so far.
            guard let month = calendar.dateInterval(of: .month, for: .now) else { return nil }
            let today = calendar.component(.day, from: .now)
            var running = 0.0
            let points = (1...today).compactMap { day -> GhafChatChart.Point? in
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: month.start) else { return nil }
                running += total(calendar.dateInterval(of: .day, for: date))
                return .init(label: "\(day)", value: running, highlight: day == today)
            }
            return GhafChatChart(kind: .trend, style: .line, title: ar ? "مصروف هذا الشهر يوماً بيوم" : "This month, day by day",
                                 currency: currency, points: points)
        }
        if has(q, ["week", "daily", "per day", "أسبوع", "اسبوع", "يومي", "يوم"]) {
            let points = (0..<7).reversed().compactMap { offset -> GhafChatChart.Point? in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
                return .init(label: day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: languageCode))),
                             value: total(calendar.dateInterval(of: .day, for: day)), highlight: offset == 0)
            }
            return GhafChatChart(kind: .week, style: requested ?? .bar, title: ar ? "آخر ٧ أيام" : "Last 7 days",
                                 currency: currency, points: points)
        }
        if requested != nil || has(q, ["categor", "where", "most", "chart", "graph", "breakdown", "stats", "spend",
                                       "فئة", "وين", "أكثر", "رسم", "مخطط", "إحصا", "احصا", "صرف"]) {
            guard let month = calendar.dateInterval(of: .month, for: .now) else { return nil }
            let byCategory = Dictionary(grouping: spending.filter { month.contains($0.date) }, by: \.category)
                .mapValues { NSDecimalNumber(decimal: $0.reduce(0) { $0 + $1.spendingAmount }).doubleValue }
                .filter { $0.value >= 1 }.sorted { $0.value > $1.value }.prefix(6)
            guard !byCategory.isEmpty else { return nil }
            return GhafChatChart(kind: .categories, style: requested ?? .bar,
                                 title: ar ? "أعلى الفئات هذا الشهر" : "Top categories this month", currency: currency,
                                 points: byCategory.enumerated().map { index, item in
                                     .init(label: GhafLocalization.category(item.key, languageCode: languageCode),
                                           value: item.value, highlight: index == 0)
                                 })
        }
        return nil
    }
}

struct GhafChatChartView: View {
    let chart: GhafChatChart
    let theme: GhafTheme
    let languageCode: String
    @State private var drawn = false
    /// The tapped or dragged-over point; nil shows the total.
    @State private var selected: String?
    @State private var selectedAngle: Double?
    /// The user can redraw the chart in place instead of asking again.
    @State private var styleOverride: GhafChatChart.Style?

    private var ar: Bool { languageCode == "ar" }
    private var style: GhafChatChart.Style { styleOverride ?? chart.style }
    private var styles: [GhafChatChart.Style] { chart.kind == .categories ? [.bar, .donut, .rose] : [.bar, .line] }
    private var total: Double { chart.points.reduce(0) { $0 + $1.value } }
    private var maxValue: Double { max(chart.points.map(\.value).max() ?? 1, 1) }
    private var selectedPoint: GhafChatChart.Point? { chart.points.first { $0.label == selected } }
    private func isDimmed(_ point: GhafChatChart.Point) -> Bool { selected != nil && selected != point.label }

    private func toggle(_ label: String) {
        withAnimation(.snappy) { selected = selected == label ? nil : label }
    }

    /// What the chart is showing right now: the selected point, or the total.
    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(selectedPoint?.label ?? (ar ? "الإجمالي" : "Total"))
                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(selectedPoint?.value ?? total, format: .number.precision(.fractionLength(0...2)))
                .font(GhafTypography.number(26, weight: .heavy))
                .foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
            Text(chart.currency)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryText)
            if let point = selectedPoint, total > 0, chart.kind == .categories {
                Text("\(Int((point.value / total * 100).rounded()))%")
                    .font(GhafTypography.number(12, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    /// Categories get one distinct colour each; time series use the theme's accent and glow.
    private func shade(_ index: Int) -> Color {
        if chart.kind == .categories {
            let colors = GhafCategoryIcon.chartColors(for: chart.points.map(\.label), dark: theme.isDark)
            return colors[chart.points[index].label] ?? theme.accent
        }
        let step = Double(index) / Double(max(chart.points.count - 1, 1))
        return index.isMultiple(of: 2) ? theme.accent.opacity(1 - step * 0.55) : theme.glow.opacity(1 - step * 0.45)
    }

    private var styleSwitch: some View {
        HStack(spacing: 2) {
            ForEach(styles, id: \.self) { item in
                Button { withAnimation(.snappy) { styleOverride = item; selected = nil } } label: {
                    Image(systemName: item == .bar ? "chart.bar.fill" : item == .donut ? "chart.pie.fill" : item == .rose ? "camera.macro" : "chart.xyaxis.line")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(style == item ? theme.accentContrast : theme.secondaryText)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                        .background(style == item ? theme.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
            }
        }
        .padding(3)
        .background(theme.elevatedSurface, in: Capsule())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chart.title)
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer(minLength: 8)
                styleSwitch
            }
            readout
            switch style {
            case .bar: bars
            case .donut: donut
            case .rose: rose
            case .line: line
            }
            Text(ar ? "اضغط أو اسحب على الرسم لرؤية التفاصيل." : "Tap or drag on the chart for details.")
                .font(GhafTypography.body(11, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme, radius: 22)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.25)) { drawn = true } }
    }

    private var bars: some View {
        Chart(chart.points) { point in
            BarMark(x: .value("Label", point.label), y: .value(chart.currency, drawn ? point.value : 0))
                .foregroundStyle(point.label == selected || (selected == nil && point.highlight)
                                 ? AnyShapeStyle(LinearGradient(colors: [theme.glow, theme.accent], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(theme.accent.opacity(isDimmed(point) ? 0.18 : 0.35)))
                .cornerRadius(7)
                .annotation(position: .top) {
                    if point.value > 0 {
                        Text(point.value, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    }
                }
        }
        .chartYAxis(.hidden)
        // Headroom so the value labels above the tallest bar are never cut off.
        .chartYScale(domain: 0...(maxValue * 1.25))
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel(collisionResolution: .greedy).font(.system(size: 11, weight: .medium)) }
        }
        .chartXSelection(value: $selected)
        .frame(height: 190)
    }

    private var donut: some View {
        VStack(spacing: 14) {
            // Slices under 2% are left out of the ring (they stay in the legend): hairline sectors crash Charts.
            Chart(Array(chart.points.enumerated()).filter { total > 0 && $0.element.value / total >= 0.02 }, id: \.element.id) { index, point in
                SectorMark(angle: .value(chart.currency, drawn ? point.value : 0.0001),
                           innerRadius: .ratio(0.62), angularInset: 2)
                    .cornerRadius(5)
                    .foregroundStyle(shade(index))
                    .opacity(isDimmed(point) ? 0.3 : 1)
            }
            .chartAngleSelection(value: $selectedAngle)
            .onChange(of: selectedAngle) { _, angle in
                guard let angle else { return }
                var running = 0.0
                if let hit = chart.points.first(where: { running += $0.value; return angle <= running }) { toggle(hit.label) }
            }
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(selectedPoint?.value ?? total, format: .number.precision(.fractionLength(0)))
                        .font(GhafTypography.number(17, weight: .heavy)).foregroundStyle(theme.primaryText)
                    Text(chart.currency).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryText)
                }
            }
            .frame(height: 200)
            legend
        }
    }

    /// Petal (polar area) chart: equal slices whose length follows the amount, like a flower.
    private var rose: some View {
        let maxValue = chart.points.map(\.value).max() ?? 1
        let count = chart.points.count
        return VStack(spacing: 12) { ZStack {
            ForEach(Array(chart.points.enumerated()), id: \.element.id) { index, point in
                let ratio = maxValue > 0 ? 0.38 + 0.62 * sqrt(point.value / maxValue) : 0.38
                GhafPetal(index: index, count: count, ratio: drawn ? ratio : 0.2)
                    .fill(shade(index))
                    .opacity(isDimmed(point) ? 0.3 : 1)
                    .contentShape(GhafPetal(index: index, count: count, ratio: ratio))
                    .onTapGesture { toggle(point.label) }
                // Labels only where the petal has room; the legend-free small ones stay readable as shape.
                if point.value >= maxValue * 0.12 {
                    GhafPetalLabel(index: index, count: count, ratio: drawn ? ratio : 0.2,
                                   value: point.value, label: point.label, color: theme.accentContrast)
                }
            }
            Circle().fill(theme.surface).frame(width: 26, height: 26).allowsHitTesting(false)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        legend }
    }

    private var line: some View {
        Chart(chart.points) { point in
            AreaMark(x: .value("Day", point.label), y: .value(chart.currency, drawn ? point.value : 0))
                .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Day", point.label), y: .value(chart.currency, drawn ? point.value : 0))
                .foregroundStyle(theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            if point.label == selected {
                RuleMark(x: .value("Day", point.label))
                    .foregroundStyle(theme.secondaryText.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Day", point.label), y: .value(chart.currency, point.value))
                    .foregroundStyle(theme.accent)
                    .symbolSize(80)
            } else if selected == nil && point.highlight {
                PointMark(x: .value("Day", point.label), y: .value(chart.currency, point.value))
                    .foregroundStyle(theme.accent)
                    .annotation(position: .top) {
                        Text(point.value, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(theme.primaryText)
                    }
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: 5)) }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(maxValue * 1.2))
        .chartXSelection(value: $selected)
        .frame(height: 180)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chart.points.enumerated()), id: \.element.id) { index, point in
                Button { toggle(point.label) } label: {
                    HStack(spacing: 6) {
                        Circle().fill(shade(index)).frame(width: 9, height: 9)
                        Text(point.label).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(point.value, format: .number.precision(.fractionLength(0))).monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                        Text(total > 0 ? "\(Int((point.value / total * 100).rounded()))%" : "–").monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .opacity(isDimmed(point) ? 0.45 : 1)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GhafPetal: Shape {
    let index: Int
    let count: Int
    var ratio: Double
    var animatableData: Double { get { ratio } set { ratio = newValue } }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * ratio
        let slice = 360.0 / Double(max(count, 1))
        let start = Angle.degrees(Double(index) * slice - 90 + 2)
        let end = Angle.degrees(Double(index + 1) * slice - 90 - 2)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct GhafPetalLabel: View {
    let index: Int
    let count: Int
    let ratio: Double
    let value: Double
    let label: String
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let slice = 360.0 / Double(max(count, 1))
            let angle = Angle.degrees(Double(index) * slice + slice / 2 - 90)
            let radius = min(geometry.size.width, geometry.size.height) / 2 * ratio * 0.68
            VStack(spacing: 0) {
                Text(value, format: .number.precision(.fractionLength(0))).font(.system(size: 12, weight: .heavy))
                Text(label).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: 64)
            }
            .foregroundStyle(color)
            .position(x: geometry.size.width / 2 + cos(angle.radians) * radius,
                      y: geometry.size.height / 2 + sin(angle.radians) * radius)
        }
    }
}
