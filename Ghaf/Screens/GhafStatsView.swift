import SwiftUI
import SwiftData
import Charts
import GhafCore

/// The Stats tab: spending over a chosen period, by time and by category, in the main currency.
/// Every chart is interactive, and the user picks how each one is drawn.
struct GhafStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    let settings: GhafSettings

    enum Period: Int, CaseIterable { case week, month, quarter, year }
    enum CategoryStyle: String, CaseIterable { case donut, bars, tiles }

    @State private var period: Period = .month
    @State private var selectedLabel: String?
    @State private var selectedCategory: String?
    @State private var selectedAngle: Double?
    @State private var showPro = false
    @State private var budgetBucket: BudgetAllocation.Bucket = .needs
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
                    AnyView(trendHero(buckets(filtered), current: current, previous: previous).ghafEntrance(0))
                    AnyView(budgetCard.ghafEntrance(1))
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
            .sheet(isPresented: $showPro) { GhafProSheet(settings: settings, feature: ("Advanced statistics", "الإحصائيات المتقدمة")) }
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
        let spent = selectedCategory == nil ? total(current) : data.reduce(0) { $0 + $1.total }
        let before = total(previous)
        let change = selectedCategory == nil && before > 0 ? (spent - before) / before : nil
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

    // MARK: Budget (50/30/20)

    /// Income for the budget period: the salary when it's set up, else the monthly income from Settings.
    private var budgetIncome: Decimal {
        settings.salaryEnabled == true ? (settings.salaryAmount ?? settings.monthlyIncome) : settings.monthlyIncome
    }

    /// The salary cycle when a salary day is set, else this calendar month (same rule as BudgetCalculator).
    private var budgetInterval: DateInterval {
        if settings.salaryEnabled == true, let day = settings.salaryDay {
            let start = GhafSalaryCycle.startDate(for: .now, salaryDay: day)
            let days = GhafSalaryCycle.daysInCycle(for: .now, salaryDay: day)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: days, to: start) ?? .now)
        }
        return calendar.dateInterval(of: .month, for: .now)!
    }

    /// Auto-allocation: income split 50/30/20, with what the ledger shows spent in needs and wants this period.
    private var budgetCard: some View {
        let income = budgetIncome
        let range = budgetInterval
        let spending = expenses(in: range)
        func spent(_ bucket: BudgetAllocation.Bucket) -> Decimal {
            spending.filter { BudgetAllocation.bucket(forCategory: $0.category) == bucket }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        }
        let needs = spent(.needs), wants = spent(.wants)
        let bucket = budgetBucket
        let planned = income * BudgetAllocation.share(bucket)
        // Savings "used" is what's actually left of income after needs and wants, against the 20% goal.
        let used: Decimal = bucket == .needs ? needs : bucket == .wants ? wants : max(income - needs - wants, 0)
        let ratio = planned > 0 ? min(max(NSDecimalNumber(decimal: used / planned).doubleValue, 0), 1.5) : 0
        let names = ar ? ["الأساسيات", "الرغبات", "الادخار"] : ["Needs", "Wants", "Savings"]
        let notes = ar ? ["إيجار، فواتير، بقالة، سيارة", "مطاعم، تسوق، ترفيه", "ما يبقى من دخلك"]
                       : ["Rent, bills, groceries, car", "Dining, shopping, fun", "What's left of your income"]
        let colors = [theme.accent, theme.glow, theme.credit]
        // Pace: spending so far against the 80% for needs and wants, prorated to today.
        let elapsed = min(max(Date.now.timeIntervalSince(range.start) / range.duration, 0.03), 1)
        let expected = NSDecimalNumber(decimal: income * 0.8).doubleValue * elapsed
        let actual = NSDecimalNumber(decimal: needs + wants).doubleValue
        let pace = expected > 0 ? (actual - expected) / expected : 0
        return VStack(spacing: 14) {
            Text(ar ? "التوزيع التلقائي" : "Auto-allocation")
                .font(GhafTypography.heading(18, languageCode: lang))
                .foregroundStyle(theme.primaryText)
            if income <= 0 {
                Text(ar ? "أضف دخلك الشهري من المزيد › الميزانية والفئات، أو راتبك من دورة الراتب، ليقسّمه غاف ٥٠/٣٠/٢٠."
                        : "Add your monthly income in More › Budget & categories, or your salary in Salary cycle, and Ghaf splits it 50/30/20.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Chart(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                    SectorMark(angle: .value("Share", NSDecimalNumber(decimal: BudgetAllocation.share(item)).doubleValue),
                               innerRadius: .ratio(0.55), outerRadius: .ratio(item == bucket ? 1 : 0.9), angularInset: 2)
                        .cornerRadius(6)
                        .foregroundStyle(colors[item.rawValue].opacity(item == bucket ? 1 : 0.35))
                }
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("\(Int(truncating: (BudgetAllocation.share(bucket) * 100) as NSNumber))%")
                            .font(GhafTypography.number(22, weight: .heavy)).foregroundStyle(theme.primaryText)
                        Text(names[bucket.rawValue]).font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(height: 170)
                .accessibilityLabel(ar ? "٥٠٪ أساسيات، ٣٠٪ رغبات، ٢٠٪ ادخار" : "Needs 50 percent, wants 30 percent, savings 20 percent")

                HStack(spacing: 4) {
                    ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                        Button { withAnimation(.snappy) { budgetBucket = item } } label: {
                            Text(names[item.rawValue])
                                .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                                .foregroundStyle(item == bucket ? theme.accentContrast : theme.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(item == bucket ? theme.accent : .clear, in: Capsule())
                        }
                        .buttonStyle(.ghafPress)
                        .accessibilityAddTraits(item == bucket ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(theme.elevatedSurface, in: Capsule())

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(names[bucket.rawValue]).font(GhafTypography.body(16, languageCode: lang, weight: .bold)).foregroundStyle(theme.primaryText)
                            Text(notes[bucket.rawValue]).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 17)
                            .foregroundStyle(theme.primaryText).environment(\.layoutDirection, .leftToRight)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.elevatedSurface)
                            Capsule().fill(bucket != .savings && ratio > 1 ? theme.over : colors[bucket.rawValue])
                                .frame(width: max(6, proxy.size.width * min(ratio, 1)))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(bucket == .savings ? (ar ? "ادّخرت حتى الآن " : "Saved so far ") + GhafFormat.shownMoney(used, currency: currency, languageCode: lang)
                                                : (ar ? "صرفت " : "Spent ") + GhafFormat.shownMoney(used, currency: currency, languageCode: lang))
                        Spacer()
                        Text((ratio).formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: lang))))
                    }
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                }
                .padding(14)
                .background(theme.elevatedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Label(pace <= 0 ? (ar ? "أقل من المخطط بـ \(Int(abs(pace) * 100))٪ حتى اليوم" : "You're \(Int(abs(pace) * 100))% under plan so far")
                                : (ar ? "أعلى من المخطط بـ \(Int(pace * 100))٪ حتى اليوم" : "You're \(Int(pace * 100))% over plan so far"),
                      systemImage: pace <= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                    .foregroundStyle(pace <= 0 ? theme.credit : theme.over)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .ghafCard(theme: theme)
        .sensoryFeedback(.selection, trigger: budgetBucket)
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
