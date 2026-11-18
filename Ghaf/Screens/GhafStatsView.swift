import SwiftUI
import SwiftData
import Charts

/// The Stats tab: spending over a chosen period, by time and by category, in the main currency.
/// Every chart is interactive, and the user picks how each one is drawn.
struct GhafStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    let settings: GhafSettings

    enum Period: Int, CaseIterable { case week, month, quarter, year }
    enum TrendStyle: String, CaseIterable { case bars, line, area }
    enum CategoryStyle: String, CaseIterable { case donut, bars, tiles }

    @State private var period: Period = .month
    @State private var selectedLabel: String?
    @State private var selectedCategory: String?
    @State private var selectedAngle: Double?
    @State private var showPro = false
    @AppStorage("ghaf.stats.trendStyle") private var trendStyle = TrendStyle.bars.rawValue
    @AppStorage("ghaf.stats.categoryStyle") private var categoryStyle = CategoryStyle.donut.rawValue

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
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    GhafScreenTitle(title: ar ? "الإحصائيات" : "Statistics",
                                    subtitle: ar ? "صرفك بالتفصيل، بعملة \(currency)" : "Your spending in detail, in \(currency)",
                                    languageCode: lang, theme: theme)
                    // Each section erased: the tab is built at launch, and deep view types overflow the stack on iOS 27.
                    AnyView(periodPicker)
                    AnyView(hero(current: current, previous: previous).ghafEntrance(0))
                    AnyView(trendCard(buckets(filtered)).ghafEntrance(1))
                    AnyView(categoryCard(slices(current)).ghafEntrance(2))
                    AnyView(metrics(current).ghafEntrance(3))
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
            .task(id: "\(period)-\(transactions.count)-\(theme.isDark)") { refreshColors() }
            .sensoryFeedback(.selection, trigger: selectedCategory)
            .sheet(isPresented: $showPro) { NavigationStack { GhafProView(settings: settings) } }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var periodPicker: some View {
        let titles = ar ? ["أسبوع", "شهر", "٣ أشهر", "سنة"] : ["Week", "Month", "3 months", "Year"]
        return HStack(spacing: 6) {
            ForEach(Period.allCases, id: \.self) { item in
                Button {
                    withAnimation(.snappy) { period = item; selectedLabel = nil; selectedCategory = nil }
                } label: {
                    Text(titles[item.rawValue])
                        .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                        .foregroundStyle(period == item ? theme.accentContrast : theme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(period == item ? theme.accent : .clear, in: Capsule())
                }
                .buttonStyle(.ghafPress)
                .accessibilityAddTraits(period == item ? .isSelected : [])
            }
        }
        .padding(5)
        .background(theme.surface, in: Capsule())
    }

    private func hero(current: [GhafTransaction], previous: [GhafTransaction]) -> some View {
        let spent = total(current), before = total(previous)
        let change = before > 0 ? (spent - before) / before : nil
        return VStack(spacing: 8) {
            Text(ar ? "المصروف" : "Spent")
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            GhafMoneyLabel(amount: Decimal(spent), currency: currency, languageCode: lang, size: 40)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
            if let change {
                Label(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(Locale(identifier: lang)))
                      + (ar ? " عن الفترة السابقة" : " vs previous"),
                      systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                    .foregroundStyle(change > 0 ? theme.over : theme.credit)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background((change > 0 ? theme.over : theme.credit).opacity(0.1), in: Capsule())
            } else {
                Text(ar ? "لا توجد بيانات للفترة السابقة" : "No data for the previous period")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .ghafCard(theme: theme)
    }

    // MARK: Trend

    private func styleSwitch<Style: RawRepresentable & CaseIterable & Hashable>(_ value: Binding<String>, _ styles: [Style],
                                                                             icons: [String], names: [String]) -> some View
    where Style.RawValue == String {
        HStack(spacing: 4) {
            ForEach(Array(styles.enumerated()), id: \.offset) { index, style in
                Button {
                    withAnimation(.snappy) { value.wrappedValue = style.rawValue }
                } label: {
                    Image(systemName: icons[index])
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(value.wrappedValue == style.rawValue ? theme.accentContrast : theme.secondaryText)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                        .background(value.wrappedValue == style.rawValue ? theme.accent : .clear, in: Capsule())
                }
                .buttonStyle(.ghafPress)
                .accessibilityLabel(names[index])
                .accessibilityAddTraits(value.wrappedValue == style.rawValue ? .isSelected : [])
            }
        }
        .padding(3)
        .background(theme.elevatedSurface, in: Capsule())
    }

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
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .quarter: return (ar ? "أسبوع " : "Week of ") + date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .year: return date.formatted(.dateTime.month(.wide).locale(locale))
        }
    }

    private func trendCard(_ data: [Bucket]) -> some View {
        // Plotted by a short label per bucket, not by date: date-unit bars by week or month crash Charts (NaN).
        let selected = selectedLabel.flatMap { label in data.first { axisLabel($0.start) == label } }
        let shown = Set(data.enumerated().filter { $0.offset % max(1, data.count / 6) == 0 }.map { axisLabel($0.element.start) })
        let sum = data.reduce(0) { $0 + $1.total }
        let style = TrendStyle(rawValue: trendStyle) ?? .bars
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.map { bucketLabel($0.start) } ?? (selectedCategory.map { GhafLocalization.category($0, languageCode: lang) }
                                                                   ?? (ar ? "على مدى الفترة" : "Over time")))
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    GhafMoneyLabel(amount: Decimal(selected?.total ?? sum), currency: currency, languageCode: lang, size: 22)
                        .foregroundStyle(theme.primaryText)
                        .contentTransition(.numericText())
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer()
                styleSwitch($trendStyle, TrendStyle.allCases, icons: ["chart.bar.fill", "chart.xyaxis.line", "chart.line.uptrend.xyaxis"],
                            names: ar ? ["أعمدة", "خط", "مساحة"] : ["Bars", "Line", "Area"])
            }
            Chart(data) { bucket in
                switch style {
                case .bars:
                    BarMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                        .foregroundStyle(selected == nil || selected?.id == bucket.id ? theme.accent.gradient : theme.accent.opacity(0.25).gradient)
                        .cornerRadius(5)
                case .line:
                    LineMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                        .foregroundStyle(theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    if selected?.id == bucket.id {
                        PointMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                            .foregroundStyle(theme.accent).symbolSize(110)
                    }
                case .area:
                    AreaMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                        .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.45), theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", axisLabel(bucket.start)), y: .value(currency, bucket.total))
                        .foregroundStyle(theme.accent)
                        .interpolationMethod(.catmullRom)
                }
                if let selected, selected.id == bucket.id {
                    RuleMark(x: .value("Date", axisLabel(bucket.start)))
                        .foregroundStyle(theme.secondaryText.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXSelection(value: $selectedLabel)
            .id(period)
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(theme.outline)
                    if !GhafFormat.balancesHidden { AxisValueLabel().foregroundStyle(theme.secondaryText) }
                }
            }
            .chartXAxis {
                AxisMarks(values: data.map { axisLabel($0.start) }.filter { shown.contains($0) }) { _ in
                    AxisValueLabel().foregroundStyle(theme.secondaryText)
                }
            }
            .frame(height: 200)
            .environment(\.layoutDirection, .leftToRight)
            .sensoryFeedback(.selection, trigger: selected?.id)
            Text(ar ? "اسحب على الرسم لرؤية كل يوم. اختر فئة بالأسفل لتصفية الرسم." : "Drag across the chart to read each point. Pick a category below to filter it.")
                .font(GhafTypography.body(11, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .ghafCard(theme: theme)
    }

    // MARK: Categories

    /// The donut's slices: anything under 2% joins "Other". Hairline sectors with rounded corners
    /// produce NaN geometry inside Charts and crash it (seen on Year, where small categories are tiny).
    private func ring(_ data: [Slice]) -> [Slice] {
        let sum = data.reduce(0) { $0 + $1.total }
        guard sum > 0 else { return [] }
        let big = data.filter { $0.total / sum >= 0.02 }
        let rest = data.filter { $0.total / sum < 0.02 }.reduce(0) { $0 + $1.total }
        guard rest > 0 else { return big }
        if let index = big.firstIndex(where: { $0.category == "Other" }) {
            var merged = big
            merged[index] = Slice(category: "Other", total: big[index].total + rest)
            return merged
        }
        return big + [Slice(category: "Other", total: rest)]
    }

    private func categoryCard(_ data: [Slice]) -> some View {
        let sum = data.reduce(0) { $0 + $1.total }
        let ringData = ring(data)
        let style = CategoryStyle(rawValue: categoryStyle) ?? .donut
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(ar ? "حسب الفئة" : "By category")
                    .font(GhafTypography.heading(18, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                styleSwitch($categoryStyle, CategoryStyle.allCases, icons: ["chart.pie.fill", "chart.bar.doc.horizontal.fill", "square.grid.2x2.fill"],
                            names: ar ? ["دائري", "أشرطة", "مربعات"] : ["Donut", "Bars", "Tiles"])
            }
            if data.isEmpty {
                Text(ar ? "لا يوجد صرف في هذه الفترة." : "No spending in this period.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                switch style {
                case .donut: donut(ringData, legendData: data, sum: sum)
                case .bars: categoryBars(data, sum: sum)
                case .tiles: tiles(data, sum: sum)
                }
            }
        }
        .padding(18)
        .ghafCard(theme: theme)
        .onChange(of: selectedAngle) { _, angle in
            guard let angle else { return }
            var running = 0.0
            let hit = ((CategoryStyle(rawValue: categoryStyle) ?? .donut) == .donut ? ringData : data).first { running += $0.total; return angle <= running }
            withAnimation(.snappy) { selectedCategory = hit?.category == selectedCategory ? nil : hit?.category }
        }
    }

    @State private var colorMap: [String: Color] = [:]
    private func color(_ category: String) -> Color { colorMap[category] ?? GhafCategoryIcon.chartColor(category, dark: theme.isDark) }
    private func refreshColors() {
        colorMap = GhafCategoryIcon.chartColors(for: slices(expenses(in: interval)).map(\.category), dark: theme.isDark)
    }

    private func toggle(_ category: String) {
        withAnimation(.snappy) { selectedCategory = selectedCategory == category ? nil : category }
    }

    private func donut(_ data: [Slice], legendData: [Slice], sum: Double) -> some View {
        let focus = data.first { $0.category == selectedCategory }
        return VStack(spacing: 16) {
            Chart(data) { slice in
                SectorMark(angle: .value(currency, slice.total), innerRadius: .ratio(0.62),
                           outerRadius: .ratio(selectedCategory == slice.category ? 1 : 0.92), angularInset: 1.5)
                    .cornerRadius(5)
                    .foregroundStyle(color(slice.category).opacity(selectedCategory == nil || selectedCategory == slice.category ? 1 : 0.3))
            }
            .chartAngleSelection(value: $selectedAngle)
            // A new chart per period: Charts animating sectors from one set of slices to another
            // produces NaN geometry and crashes (seen switching to 3 months and Year).
            .id(period)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(focus.map { GhafLocalization.category($0.category, languageCode: lang) } ?? (ar ? "المجموع" : "Total"))
                        .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    GhafMoneyLabel(amount: Decimal(focus?.total ?? sum), currency: currency, languageCode: lang, size: 18)
                        .foregroundStyle(theme.primaryText)
                        .environment(\.layoutDirection, .leftToRight)
                    if let focus, sum > 0 {
                        Text((focus.total / sum).formatted(.percent.precision(.fractionLength(0))))
                            .font(GhafTypography.number(12, weight: .bold))
                            .foregroundStyle(color(focus.category))
                    }
                }
            }
            .frame(height: 220)
            legend(legendData, sum: sum)
        }
    }

    private func legend(_ data: [Slice], sum: Double) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(data.prefix(8)) { slice in
                Button { toggle(slice.category) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(color(slice.category)).frame(width: 10, height: 10)
                        Text(GhafLocalization.category(slice.category, languageCode: lang))
                            .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.primaryText).lineLimit(1)
                        Spacer(minLength: 2)
                        Text((slice.total / max(sum, 1)).formatted(.percent.precision(.fractionLength(0))))
                            .font(GhafTypography.number(12, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, 10).frame(minHeight: 40)
                    .background(selectedCategory == slice.category ? color(slice.category).opacity(0.14) : theme.elevatedSurface,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.ghafPress)
            }
        }
    }

    private func categoryBars(_ data: [Slice], sum: Double) -> some View {
        VStack(spacing: 10) {
            ForEach(data) { slice in
                Button { toggle(slice.category) } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            GhafCategoryIcon(category: slice.category, tint: theme.accent).scaleEffect(0.8).frame(width: 36, height: 36)
                            Text(GhafLocalization.category(slice.category, languageCode: lang))
                                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            GhafMoneyLabel(amount: Decimal(slice.total), currency: currency, languageCode: lang, size: 14)
                                .foregroundStyle(theme.primaryText)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(theme.elevatedSurface)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(color(slice.category))
                                        .frame(width: max(6, proxy.size.width * slice.total / max(sum, 1)))
                                }
                        }
                        .frame(height: 8)
                    }
                    .opacity(selectedCategory == nil || selectedCategory == slice.category ? 1 : 0.4)
                }
                .buttonStyle(.ghafPress)
            }
        }
    }

    private func tiles(_ data: [Slice], sum: Double) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(data.prefix(8)) { slice in
                Button { toggle(slice.category) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            GhafCategoryIcon(category: slice.category, tint: theme.accent).scaleEffect(0.8).frame(width: 36, height: 36)
                            Spacer()
                            Text((slice.total / max(sum, 1)).formatted(.percent.precision(.fractionLength(0))))
                                .font(GhafTypography.number(18, weight: .heavy))
                                .foregroundStyle(color(slice.category))
                        }
                        Text(GhafLocalization.category(slice.category, languageCode: lang))
                            .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.secondaryText).lineLimit(1)
                        GhafMoneyLabel(amount: Decimal(slice.total), currency: currency, languageCode: lang, size: 16)
                            .foregroundStyle(theme.primaryText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color(slice.category).opacity(selectedCategory == slice.category ? 0.2 : 0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.ghafPress)
            }
        }
    }

    // MARK: Metrics and merchants

    private func metrics(_ items: [GhafTransaction]) -> some View {
        let spent = total(items)
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: min(Date.now, interval.end)).day ?? 1)
        let biggest = items.max { $0.amount < $1.amount }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric(ar ? "متوسط اليوم" : "Daily average", icon: "calendar") {
                GhafMoneyLabel(amount: Decimal(spent / Double(days)), currency: currency, languageCode: lang, size: 18)
            }
            metric(ar ? "عدد العمليات" : "Transactions", icon: "number") {
                Text(items.count.formatted(.number.locale(Locale(identifier: lang)))).font(GhafTypography.number(20, weight: .heavy))
            }
            metric(ar ? "أكبر عملية" : "Biggest purchase", icon: "arrow.up.circle", detail: biggest?.merchant) {
                GhafMoneyLabel(amount: biggest?.amount ?? 0, currency: currency, languageCode: lang, size: 18)
            }
            metric(ar ? "الفئة الأعلى" : "Top category", icon: "crown") {
                Text(slices(items).first.map { GhafLocalization.category($0.category, languageCode: lang) } ?? "—")
                    .font(GhafTypography.body(17, languageCode: lang, weight: .bold)).lineLimit(1)
            }
        }
    }

    private func metric<Value: View>(_ title: String, icon: String, detail: String? = nil, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            value().foregroundStyle(theme.primaryText)
            if let detail {
                Text(detail).font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .ghafCard(theme: theme, radius: 18)
    }

    private func merchants(_ items: [GhafTransaction]) -> some View {
        let top = Dictionary(grouping: items.filter { $0.merchant?.isEmpty == false }, by: { $0.merchant! })
            .map { (name: $0.key, total: total($0.value), count: $0.value.count) }
            .sorted { $0.total > $1.total }
            .prefix(5)
        let most = top.first?.total ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text(ar ? "أين صرفت أكثر" : "Where it went")
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
                GhafTreeShape().fill(theme.accentContrast).frame(width: 34, height: 34)
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
