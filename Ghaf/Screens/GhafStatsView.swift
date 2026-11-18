import SwiftUI
import SwiftData
import Charts
import GhafCore

/// The Stats tab: spending over a chosen period, by time and by category, in the main currency.
/// Laid out like the approved canvas: trend hero, "Where it went" bars, two tiles, merchants.
struct GhafStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    let settings: GhafSettings

    enum Period: Int, CaseIterable { case week, month, quarter, year }

    @State private var period: Period = .month
    @State private var selectedLabel: String?
    @State private var selectedCategory: String?
    @State private var showPro = false

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var currency: String { settings.currency }
    private var calendar: Calendar { GhafCalendar.current }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    // MARK: Data

    private struct Bucket: Identifiable { let start: Date; let total: Double; var id: Date { start } }
    private struct Slice: Identifiable { let category: String; let total: Double; var id: String { category } }

    private var interval: DateInterval {
        let now = Date.now
        switch period {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: now)!
        case .month: return calendar.dateInterval(of: .month, for: now)!
        case .quarter:
            let start = calendar.date(byAdding: .month, value: -2, to: calendar.dateInterval(of: .month, for: now)!.start)!
            return DateInterval(start: start, end: calendar.dateInterval(of: .month, for: now)!.end)
        case .year: return calendar.dateInterval(of: .year, for: now)!
        }
    }

    private var previousInterval: DateInterval {
        let length: DateComponents = switch period {
        case .week: DateComponents(weekOfYear: -1)
        case .month: DateComponents(month: -1)
        case .quarter: DateComponents(month: -3)
        case .year: DateComponents(year: -1)
        }
        return DateInterval(start: calendar.date(byAdding: length, to: interval.start)!, end: interval.start)
    }

    private var bucketUnit: Calendar.Component {
        switch period { case .week, .month: .day; case .quarter: .weekOfYear; case .year: .month }
    }

    private func expenses(in range: DateInterval) -> [GhafTransaction] {
        transactions.filter { $0.currency == currency && $0.isExpense && range.contains($0.date) }
    }

    private func total(_ items: [GhafTransaction]) -> Double {
        NSDecimalNumber(decimal: items.reduce(Decimal.zero) { $0 + $1.spendingAmount }).doubleValue
    }

    private func buckets(_ items: [GhafTransaction]) -> [Bucket] {
        var starts: [Date] = []
        var cursor = calendar.dateInterval(of: bucketUnit, for: interval.start)!.start
        while cursor < interval.end {
            starts.append(cursor)
            cursor = calendar.date(byAdding: bucketUnit, value: 1, to: cursor)!
        }
        var sums = [Date: Double]()
        for item in items {
            guard let start = calendar.dateInterval(of: bucketUnit, for: item.date)?.start else { continue }
            sums[start, default: 0] += NSDecimalNumber(decimal: item.spendingAmount).doubleValue
        }
        return starts.map { Bucket(start: $0, total: sums[$0] ?? 0) }
    }

    private func slices(_ items: [GhafTransaction]) -> [Slice] {
        Dictionary(grouping: items, by: \.category)
            .map { Slice(category: $0.key, total: total($0.value)) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    // MARK: Body

    var body: some View {
        let current = expenses(in: interval)
        let previous = expenses(in: previousInterval)
        let filtered = selectedCategory.map { category in current.filter { $0.category == category } } ?? current
        // With a category picked, the hero compares that category against itself last period.
        let previousFiltered = selectedCategory.map { category in previous.filter { $0.category == category } } ?? previous
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    GhafScreenTitle(title: ar ? "الإحصائيات" : "Statistics",
                                    subtitle: nil,
                                    languageCode: lang, theme: theme)
                    // Each section erased: the tab is built at launch, and deep view types overflow the stack on iOS 27.
                    AnyView(trendHero(buckets(filtered), current: filtered, previous: previousFiltered).ghafEntrance(0))
                    AnyView(whereItWent(slices(current)).ghafEntrance(1))
                    AnyView(tiles(current).ghafEntrance(2))
                    AnyView(budgetLink.ghafEntrance(3))
                    AnyView(merchants(current).ghafEntrance(4))
                    AnyView(proCard.ghafEntrance(5))
                }
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: period)
            .sensoryFeedback(.selection, trigger: selectedCategory)
            .sheet(isPresented: $showPro) { GhafProSheet(settings: settings, feature: ("Advanced statistics", "الإحصائيات المتقدمة")).ghafDirection(settings.languageCode) }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    // MARK: Trend hero

    /// Short, unique label for a bucket on the chart's axis.
    private func axisLabel(_ date: Date) -> String {
        let locale = Locale(identifier: lang)
        switch period {
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        case .month: return date.formatted(.dateTime.day().locale(locale))
        case .quarter: return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .year: return date.formatted(.dateTime.month(.abbreviated).locale(locale))
        }
    }

    private func bucketLabel(_ date: Date) -> String {
        let locale = Locale(identifier: lang)
        switch period {
        case .week: return date.formatted(.dateTime.weekday(.wide).locale(locale))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .quarter: return (ar ? "أسبوع " : "Week of ") + date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .year: return date.formatted(.dateTime.month(.wide).locale(locale))
        }
    }

    /// One card in the theme's surface, Stocks style: the total (or the scrubbed point), the change against the previous
    /// period, a line you drag across, and the period chips under it. Every value comes from the ledger.
    private func trendHero(_ all: [Bucket], current: [GhafTransaction], previous: [GhafTransaction]) -> some View {
        // Days that haven't happened yet aren't zero spending: the line stops at today, like Stocks.
        let data = all.filter { $0.start <= .now }
        // Plotted by a short label per bucket, not by date: date-unit marks by week or month crash Charts (NaN).
        let selected = selectedLabel.flatMap { label in data.first { axisLabel($0.start) == label } }
        let shown = Set(data.enumerated().filter { $0.offset % max(1, data.count / 6) == 0 }.map { axisLabel($0.element.start) })
        let spent = total(current)
        let before = total(previous)
        let change = before > 0 ? (spent - before) / before : nil
        let accent = theme.accent
        let periods = ar ? ["أ", "ش", "٣ش", "س"] : ["W", "M", "3M", "Y"]
        let periodNames = ar ? ["أسبوع", "شهر", "٣ أشهر", "سنة"] : ["Week", "Month", "3 months", "Year"]
        let heading = selected.map { bucketLabel($0.start) }
            ?? selectedCategory.map { GhafLocalization.category($0, languageCode: lang) }
            ?? (ar ? "المصروف · \(periodNames[period.rawValue])" : "Spent · \(periodNames[period.rawValue])")
        return VStack(spacing: 6) {
            Text(heading)
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .contentTransition(.opacity)
            GhafMoneyLabel(amount: Decimal(selected?.total ?? spent), currency: currency, languageCode: lang, size: 38)
                .foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
                .environment(\.layoutDirection, .leftToRight)
            if let change, selected == nil {
                Label(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(Locale(identifier: lang)))
                      + (ar ? " عن الفترة السابقة" : " vs previous"),
                      systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .bold))
                    .foregroundStyle(change > 0 ? theme.over : theme.credit)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((change > 0 ? theme.over : theme.credit).opacity(0.16), in: Capsule())
            } else {
                Text(selected != nil ? (ar ? "ارفع إصبعك لرؤية المجموع" : "Lift your finger to see the total")
                                     : (ar ? "لا توجد بيانات للفترة السابقة" : "No data for the previous period"))
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.vertical, 5)
            }
            Chart(data) { bucket in
                AreaMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.4), accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                    .foregroundStyle(accent)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if let selected, selected.id == bucket.id {
                    RuleMark(x: .value("Date", axisLabel(bucket.start)))
                        .foregroundStyle(theme.secondaryText.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    PointMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                        .symbol { Circle().fill(accent).frame(width: 14, height: 14).overlay(Circle().stroke(theme.surface, lineWidth: 3)) }
                        .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(axisLabel(bucket.start))
                                .font(GhafTypography.body(11, languageCode: lang, weight: .bold))
                                .foregroundStyle(theme.surface)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(theme.primaryText, in: Capsule())
                        }
                }
            }
            .chartXSelection(value: $selectedLabel)
            // A new chart per period, faded in: Charts animating between different label sets produces NaN geometry.
            .id(period)
            .transition(.opacity)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: data.map { axisLabel($0.start) }.filter { shown.contains($0) }) { _ in
                    AxisValueLabel().foregroundStyle(theme.secondaryText)
                }
            }
            .frame(height: 180)
            .padding(.top, 14)
            .environment(\.layoutDirection, .leftToRight)
            .sensoryFeedback(.selection, trigger: selected?.id)
            .accessibilityLabel(ar ? "اتجاه الصرف، اسحب لقراءة كل نقطة" : "Spending trend; drag to read each point")

            HStack(spacing: 6) {
                ForEach(Period.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.snappy) { period = item; selectedLabel = nil; selectedCategory = nil }
                    } label: {
                        Text(periods[item.rawValue])
                            .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                            .foregroundStyle(period == item ? theme.accentContrast : theme.secondaryText)
                            .frame(minWidth: 54, minHeight: 40)
                            .background(period == item ? accent : theme.elevatedSurface, in: Capsule())
                    }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(periodNames[item.rawValue])
                    .accessibilityAddTraits(period == item ? .isSelected : [])
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 20)
        .ghafCard(theme: theme, radius: 30)
    }

    // MARK: Budget entry

    private var budgetLink: some View {
        NavigationLink { GhafBudgetView(settings: settings) } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.accentContrast)
                    .frame(width: 40, height: 40).background(theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(ar ? "الميزانية" : "Budget").font(GhafTypography.body(15, languageCode: lang, weight: .bold)).foregroundStyle(theme.primaryText)
                    Text(ar ? "الراتب والتوزيع ٥٠/٣٠/٢٠ والوتيرة" : "Salary, 50/30/20 split and pace")
                        .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 4)
                Image(systemName: ar ? "chevron.left" : "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.primaryText)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .ghafCard(theme: theme, radius: 22)
        }
        .buttonStyle(.ghafPress)
    }

    // MARK: Where it went

    /// Canvas "Where it went": the five biggest categories as tappable bars; a tap filters the hero line.
    private func whereItWent(_ data: [Slice]) -> some View {
        let top = Array(data.prefix(5))
        let most = top.first?.total ?? 1
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ar ? "أين ذهب المال" : "Where it went")
                    .font(GhafTypography.heading(16, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(ar ? "اضغط شريطاً لتصفية الرسم" : "Tap a bar to filter the chart")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            if top.isEmpty {
                Text(ar ? "لا يوجد صرف في هذه الفترة." : "No spending in this period.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(top) { slice in
                        let on = selectedCategory == slice.category
                        Button { toggle(slice.category) } label: {
                            VStack(spacing: 6) {
                                Spacer(minLength: 0)
                                Text(whole(slice.total))
                                    .font(GhafTypography.number(11, weight: .bold))
                                    .foregroundStyle(on ? theme.primaryText : theme.secondaryText)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(on ? theme.accent : theme.primaryText.opacity(0.09))
                                    .frame(height: max(10, 92 * slice.total / most))
                                Text(GhafLocalization.category(slice.category, languageCode: lang))
                                    .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText)
                                    // Two lines: Arabic names like "السيارة والمواصلات" don't fit one.
                                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.ghafPress)
                        .accessibilityLabel("\(GhafLocalization.category(slice.category, languageCode: lang)) \(GhafFormat.shownMoney(Decimal(slice.total), currency: currency, languageCode: lang))")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .ghafCard(theme: theme, radius: 24)
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: lang)))
    }

    private func toggle(_ category: String) {
        withAnimation(.snappy) { selectedCategory = selectedCategory == category ? nil : category }
    }

    // MARK: Tiles and merchants

    private func tiles(_ items: [GhafTransaction]) -> some View {
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: min(Date.now, interval.end)).day ?? 1)
        let units = ar ? ["هذا الأسبوع", "هذا الشهر", "آخر ٣ أشهر", "هذه السنة"] : ["this week", "this month", "these 3 months", "this year"]
        return HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(ar ? "متوسط اليوم" : "Daily average")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .bold))
                    .foregroundStyle(theme.accentContrast.opacity(0.65))
                Text(whole(total(items) / Double(days)))
                    .font(GhafTypography.number(26, weight: .bold))
                    .foregroundStyle(theme.accentContrast)
                Text(ar ? "\(currency) يومياً" : "\(currency) a day")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.accentContrast.opacity(0.65))
            }
            .frame(maxWidth: .infinity).padding(14)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(spacing: 2) {
                Text(ar ? "المشتريات" : "Purchases")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                Text(items.count.formatted(.number.locale(Locale(identifier: lang))))
                    .font(GhafTypography.number(26, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(units[period.rawValue])
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity).padding(14)
            .ghafCard(theme: theme, radius: 22)
        }
    }

    private func merchants(_ items: [GhafTransaction]) -> some View {
        let top = Dictionary(grouping: items.filter { $0.merchant?.isEmpty == false }, by: { $0.merchant! })
            .map { (name: $0.key, total: total($0.value), count: $0.value.count) }
            .sorted { $0.total > $1.total }
            .prefix(5)
        let most = top.first?.total ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text(ar ? "أكثر المتاجر" : "Top merchants")
                .font(GhafTypography.heading(18, languageCode: lang))
                .foregroundStyle(theme.primaryText)
            if top.isEmpty {
                Text(ar ? "لا توجد متاجر في هذه الفترة." : "No merchants in this period.")
                    .font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
            }
            ForEach(Array(top), id: \.name) { row in
                HStack(spacing: 12) {
                    GhafBrandBadge(name: row.name, fallbackTint: theme.accent, size: 36)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.name).font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                                .foregroundStyle(theme.primaryText).lineLimit(1)
                            Spacer()
                            GhafMoneyLabel(amount: Decimal(row.total), currency: currency, languageCode: lang, size: 14)
                                .foregroundStyle(theme.primaryText)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(theme.accent.opacity(0.85)).frame(width: max(6, proxy.size.width * row.total / most))
                        }
                        .frame(height: 5)
                        Text(ar ? "\(row.count) عملية" : "\(row.count) purchases")
                            .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme)
    }

    private var proCard: some View {
        Button { showPro = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.accentContrast)
                    .frame(width: 54, height: 54)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ghaf Pro").font(GhafTypography.heading(17, languageCode: lang)).foregroundStyle(theme.primaryText)
                    Text(ar ? "تقارير أعمق، ودجت، ونشاط مباشر على شاشة القفل." : "Deeper reports, widgets and Live Activities on your Lock Screen.")
                        .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: ar ? "chevron.left" : "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.secondaryText)
            }
            .padding(16)
            .ghafCard(theme: theme)
        }
        .buttonStyle(.ghafPress)
    }
}
