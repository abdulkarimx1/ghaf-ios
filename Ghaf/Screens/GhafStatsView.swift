import SwiftUI
import SwiftData
import Charts
import GhafCore

/// The Stats tab: spending over a chosen period, by time and by category, in the main currency.
/// Laid out like the approved canvas: trend hero, "Where it went" bars, two tiles, merchants.
struct GhafStatsView: View {
    @Environment(GhafTabRouter.self) private var router
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    @Query private var subscriptions: [GhafSubscription]
    let settings: GhafSettings

    enum Period: Int, CaseIterable { case week, month, quarter, year }

    private static var fixturePeriod: Period {
#if DEBUG
        switch GhafScreenshotFixture.period {
        case "W": .week
        case "3M": .quarter
        case "Y": .year
        default: .month
        }
#else
        .month
#endif
    }
    @State private var period: Period
    @State private var chartDrawProgress = 1.0
    @State private var chartReady = false
    @State private var selectedLabel: String?
    @State private var selectedCategory: String?
    @State private var showProSheet = false
    @State private var barTransactions: BarTransactions?
    private struct BarTransactions: Identifiable { let id = UUID(); let title: String; let items: [GhafTransaction] }
    @State private var preparedStats = PreparedStats.empty
    @State private var cachedStatsID: String?

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var currency: String { settings.currency }
    private var proUnlocked: Bool { GhafProAccess.hasAccess }
    private var calendar: Calendar { GhafCalendar.current }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }
    private var fixtureBudget: Bool {
#if DEBUG
        GhafScreenshotFixture.enabled && GhafScreenshotFixture.destination == "budget"
#else
        false
#endif
    }

    init(settings: GhafSettings, initialPeriod: Period? = nil) {
        self.settings = settings
        _period = State(initialValue: initialPeriod ?? Self.fixturePeriod)
    }

    // MARK: Data

    private struct Bucket: Identifiable { let start: Date; let end: Date; let total: Double; let forecast: Double?; var id: Date { start } }
    private struct DayBar: Identifiable { let date: Date; let amount: Double; let forecast: Bool; var id: Date { date } }
    private struct Slice: Identifiable { let category: String; let total: Double; var id: String { category } }
    private struct PreparedStats {
        let current: [GhafTransaction]
        let filtered: [GhafTransaction]
        let previousFiltered: [GhafTransaction]
        let buckets: [Bucket]
        let slices: [Slice]
        let transferTotal: Decimal
        let hasPreviousCoverage: Bool

        static let empty = PreparedStats(current: [], filtered: [], previousFiltered: [], buckets: [],
                                         slices: [], transferTotal: .zero, hasPreviousCoverage: false)
    }

    private var statsTaskID: String {
        "\(transactions.count)-\(subscriptions.count)-\(period.rawValue)-\(selectedCategory ?? "")-\(currency)-\(router.ledgerRevision)"
    }

    private func refreshStatsIfNeeded() {
        let currentID = statsTaskID
        guard currentID != cachedStatsID else { return }
#if DEBUG
        preparedStats = GhafPerformanceProbe.measure("stats-summary") { prepareStats() }
#else
        preparedStats = prepareStats()
#endif
        cachedStatsID = currentID
    }

    private var interval: DateInterval {
        let now = GhafClock.now
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

    private func expenses(in range: DateInterval) -> [GhafTransaction] {
        transactions.filter { $0.currency == currency && $0.isExpense && range.contains($0.date) }
    }

    private func outgoingTransferAmount(_ transaction: GhafTransaction) -> Decimal {
        let isAdjustment = transaction.category == "Adjustment"
        let transferCategory = CategoryTaxonomy.category(named: transaction.category)?.kind == .transfer
        let hasTransferEvidence = TransactionEffect.isKnownExternalTransferSubcategory(transaction.subcategory)
            || (transferCategory && transaction.subcategory == nil)
        let isTransfer = !isAdjustment
            && CategoryTaxonomy.isTransferOrAdjustment(category: transaction.category, subcategory: transaction.subcategory)
            && hasTransferEvidence
        let ownAccountCategory = CategoryTaxonomy.transferSubcategories.first { $0.name == "Between my accounts" }
        let ownAccountNames = Set(([ownAccountCategory?.name, ownAccountCategory?.arabic].compactMap { $0 } + (ownAccountCategory?.words ?? []))
            .map(CategoryMatcher.normalize))
        let isOwnAccountTransfer = transaction.subcategory.map { ownAccountNames.contains(CategoryMatcher.normalize($0)) } ?? false
        return TransactionEffect.outgoingTransfer(amount: transaction.amount, isDebit: transaction.direction == "debit",
                                                   isReversal: transaction.isReversal, isTransfer: isTransfer,
                                                   isBetweenOwnAccounts: isOwnAccountTransfer)
    }

    private func outgoingTransfers(in range: DateInterval) -> [GhafTransaction] {
        transactions.filter {
            $0.currency == currency && range.contains($0.date) && outgoingTransferAmount($0) > 0
        }
    }

    private func statisticsAmount(_ transaction: GhafTransaction) -> Decimal {
        transaction.isSpendingOrIncome ? transaction.spendingAmount : outgoingTransferAmount(transaction)
    }

    private func total(_ items: [GhafTransaction]) -> Double {
        NSDecimalNumber(decimal: items.reduce(Decimal.zero) { $0 + statisticsAmount($1) }).doubleValue
    }

    /// Points on the trend line: one per day for week, month and 3 months; one per month for the year.
    private func bucketWindows() -> [SpendingForecast.Window] {
        guard period == .month || period == .quarter else { return groupWindows() }
        // Owner #51: daily points made Month/3M spiky and condensed. Like Year (~12 points): 3-day steps for Month, weekly for 3M.
        let step = period == .month ? 3 : 7
        var windows: [SpendingForecast.Window] = []
        var day = interval.start
        while day < interval.end, let next = calendar.date(byAdding: .day, value: step, to: day) {
            windows.append(.init(start: day, end: min(next, interval.end))); day = next
        }
        return windows
    }

    /// The four even groups for Month and 3M (they label the x-axis); same as the points for Week and Year.
    private func groupWindows() -> [SpendingForecast.Window] {
        let corePeriod: SpendingInsights.ChartPeriod = switch period {
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
        return SpendingInsights.chartWindows(period: corePeriod, start: interval.start, end: interval.end, calendar: calendar)
            .map { SpendingForecast.Window(start: $0.start, end: $0.end) }
    }

    private func buckets(_ items: [GhafTransaction]) -> [Bucket] {
        let windows = bucketWindows()
        let forecastExpenses = transactions.compactMap { item -> SpendingForecast.Expense? in
            guard item.currency == currency, item.isExpense, item.spendingAmount > 0,
                  selectedCategory == nil || item.category == selectedCategory else { return nil }
            return SpendingForecast.Expense(date: item.date, amount: item.spendingAmount, isTransfer: !item.isSpendingOrIncome)
        }
        let forecastSubscriptions = subscriptions.filter { $0.currency == currency && (selectedCategory == nil || selectedCategory == "Subscriptions") }.map {
            SpendingForecast.Subscription(nextPaymentDate: $0.nextPaymentDate, amount: $0.amount, isActive: $0.isActive)
        }
        let forecasts = SpendingForecast.amounts(expenses: forecastExpenses, subscriptions: forecastSubscriptions,
                                                 windows: windows, now: GhafClock.now, calendar: calendar)
        return windows.map { window in
            let actual = items.filter { window.start <= $0.date && $0.date < window.end }
                .reduce(Decimal.zero) { $0 + statisticsAmount($1) }
            return Bucket(start: window.start, end: window.end,
                          total: NSDecimalNumber(decimal: actual).doubleValue,
            forecast: forecasts[window.start].map { NSDecimalNumber(decimal: $0).doubleValue })
        }
    }

    private func slices(_ items: [GhafTransaction]) -> [Slice] {
        Dictionary(grouping: items, by: \.category)
            .map { Slice(category: $0.key, total: total($0.value)) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    private func prepareStats() -> PreparedStats {
        let current = expenses(in: interval)
        let previous = expenses(in: previousInterval)
        let currentTransfers = outgoingTransfers(in: interval)
        let previousTransfers = outgoingTransfers(in: previousInterval)
        let filtered: [GhafTransaction]
        let previousFiltered: [GhafTransaction]
        if selectedCategory == "Transfers" {
            filtered = currentTransfers
            previousFiltered = previousTransfers
        } else {
            filtered = selectedCategory.map { category in current.filter { $0.category == category } } ?? current
            previousFiltered = selectedCategory.map { category in previous.filter { $0.category == category } } ?? previous
        }
        let transferTotal = currentTransfers.reduce(Decimal.zero) { $0 + outgoingTransferAmount($1) }
        let firstTransactionDate = transactions.lazy.filter { $0.currency == currency }.map(\.date).min()
        let hasPreviousCoverage = SpendingForecast.hasPreviousPeriodCoverage(firstTransactionDate: firstTransactionDate,
                                                                               start: previousInterval.start, end: previousInterval.end, calendar: calendar)
        return PreparedStats(current: current, filtered: filtered, previousFiltered: previousFiltered,
                             buckets: buckets(filtered), slices: slices(current), transferTotal: transferTotal,
                             hasPreviousCoverage: hasPreviousCoverage)
    }

    // MARK: Body

    var body: some View {
        let stats = preparedStats
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Group {
                    if fixtureBudget {
                    GhafBudgetView(settings: settings)
                    } else {
                        ScrollView {
                            VStack(spacing: GhafMetrics.sectionSpacing) {
                                GhafScreenTitle(title: ar ? "الإحصائيات" : "Statistics",
                                                subtitle: nil,
                                                languageCode: lang, theme: theme)
                                // Each section erased: the tab is built at launch, and deep view types overflow the stack on iOS 27.
                                let trendBuckets = stats.buckets
                                AnyView(trendHero(trendBuckets, current: stats.filtered, previous: stats.previousFiltered,
                                                  hasPreviousCoverage: stats.hasPreviousCoverage)).id("trend-chart")
                                AnyView(whereItWent(stats.slices, transferTotal: stats.transferTotal)).id("category-chart")
                                AnyView(tiles(stats.current))
                                AnyView(budgetLink)
                                AnyView(merchants(stats.current))
                                AnyView(proCard)
                            }
                            .ghafScreenPadding()
                            .padding(.top, 12)
                            .padding(.bottom, 30)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                        }
                        .ghafReportsTabBarMinimize()
                        .scrollIndicators(.hidden)
                        .ghafStatusBarFade(theme: theme)
                    }
                }
                .ghafBackground(theme: theme)
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: statsTaskID) { _, _ in refreshStatsIfNeeded() }
                .onAppear { refreshStatsIfNeeded() }
                .sensoryFeedback(.selection, trigger: period)
                .sensoryFeedback(.selection, trigger: selectedCategory)
                .sheet(isPresented: $showProSheet) { GhafProSheet(settings: settings, feature: ("Advanced statistics", "الإحصائيات المتقدمة")).ghafDirection(settings.languageCode) }
                .sheet(item: $barTransactions) { bar in
                    GhafTransactionListSheet(title: bar.title, transactions: bar.items, theme: theme, languageCode: lang)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .ghafSheetFrame(theme: theme)
                        .ghafDirection(lang)
                }
                .onChange(of: router.statsFocus) { _, _ in applyStatsFocus() }
                .onAppear {
                chartReady = true
                applyStatsFocus()
#if DEBUG
                guard GhafScreenshotFixture.enabled else { return }
                if GhafScreenshotFixture.destination == "pro-popup" || GhafScreenshotFixture.destination == "pro-sheet" { showProSheet = true }
                if GhafScreenshotFixture.selection == "bar" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        selectedLabel = preparedStats.buckets.last(where: { $0.total > 0 }).map { chartKey($0.start) }
                        if GhafScreenshotFixture.destination == "bar-sheet", let key = selectedLabel,
                           let bucket = preparedStats.buckets.first(where: { chartKey($0.start) == key }) {
                            barTransactions = BarTransactions(title: bucketLabel(bucket.start),
                                items: preparedStats.filtered.filter { $0.date >= bucket.start && $0.date < bucket.end })
                        }
                    }
                }
                if GhafScreenshotFixture.selection == "point" {
                    let date = calendar.dateInterval(of: .day, for: GhafClock.now.addingTimeInterval(-9 * 86_400))?.start ?? GhafClock.now
                    selectedLabel = chartKey(calendar.startOfDay(for: date))
                }
                if GhafScreenshotFixture.selection == "category" { selectedCategory = "Dining" }
                if GhafScreenshotFixture.autoSelect && !fixtureBudget { runAutoSelection(scrollProxy: scrollProxy) }
                if GhafScreenshotFixture.selection == "category" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scrollProxy.scrollTo("category-chart", anchor: .center) }
                }

#endif
                }
            }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    // MARK: Trend hero

    /// Short, unique label for a bucket on the chart's axis.
    private func axisLabel(_ date: Date) -> String {
        let locale = Locale(identifier: lang)
        switch period {
        case .week: return date.formatted(.dateTime.weekday(.narrow).locale(locale))
        case .month, .quarter:
            // 4 even bars: label each with its date range, e.g. "1–8" or "1 Sep".
            // Labels sit under the middle day of each group; show that group's range.
            let group = groupWindows().first(where: { $0.start <= date && date < $0.end })
            let start = group?.start ?? date
            let end = calendar.date(byAdding: .day, value: -1, to: group?.end ?? interval.end)!
            return period == .month
                ? "\(start.formatted(.dateTime.day().locale(locale)))–\(end.formatted(.dateTime.day().locale(locale)))"
                : start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .year:
            return date.formatted(.dateTime.month(ar ? .wide : .abbreviated).locale(locale))
        }
    }

    private func applyStatsFocus() {
        guard let focus = router.statsFocus, let target = Period(rawValue: focus.period) else { return }
        router.statsFocus = nil
        period = target
        // Changing period clears the selection, so select the day once that has run.
        guard let day = focus.day else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(.snappy) { selectedLabel = chartKey(calendar.startOfDay(for: day)) } }
    }

    private func chartKey(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    private func bucketLabel(_ date: Date) -> String {
        let locale = Locale(identifier: lang)
        switch period {
        case .month, .quarter:
            // A point now covers several days, so name its range: "4–6 Nov", or "30 Oct – 5 Nov" across months.
            let window = bucketWindows().first(where: { $0.start <= date && date < $0.end })
            let last = calendar.date(byAdding: .day, value: -1, to: window?.end ?? date) ?? date
            if calendar.isDate(date, inSameDayAs: last) { return date.formatted(.dateTime.day().month(.abbreviated).locale(locale)) }
            if calendar.isDate(date, equalTo: last, toGranularity: .month) {
                return "\(date.formatted(.dateTime.day().locale(locale)))–\(last.formatted(.dateTime.day().locale(locale))) \(last.formatted(.dateTime.month(.abbreviated).locale(locale)))"
            }
            return "\(date.formatted(.dateTime.day().month(.abbreviated).locale(locale))) – \(last.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"
        case .week: return date.formatted(.dateTime.weekday(.wide).locale(locale))
        case .year: return date.formatted(.dateTime.month(.wide).locale(locale))
        }
    }

    @ChartContentBuilder
    private func actualTrendMark(_ bucket: Bucket) -> some ChartContent {
        // Owner 1.31: one smooth line (with a soft fill) over the period; the scrubbed point is marked separately.
        AreaMark(x: .value("Date", chartKey(bucket.start)), yStart: .value("Baseline", 0), yEnd: .value(currency, bucket.total), series: .value("Series", "Actual"))
            .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.28), theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)
        LineMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total), series: .value("Series", "Actual"))
            .foregroundStyle(theme.accent)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
    }

    /// One card in the theme's surface, Stocks style: the total (or the scrubbed point), the change against the previous
    /// period, a line you drag across, and the period chips under it. Every value comes from the ledger.
    private func trendHero(_ all: [Bucket], current: [GhafTransaction], previous: [GhafTransaction],
                           hasPreviousCoverage: Bool) -> some View {
        let plotted = all.filter { $0.start <= GhafClock.now || $0.forecast != nil }
        let forecastPoints: [(Bucket, Double)] = {
            guard let first = plotted.firstIndex(where: { $0.forecast != nil }) else { return [] }
            return plotted[max(0, first - 1)...].map { ($0, $0.total + ($0.forecast ?? 0)) }
        }()
        let selected = selectedLabel.flatMap { key in plotted.first { chartKey($0.start) == key } }
        let spent = total(current)
        let before = total(previous)
        let change = before > 0 ? (spent - before) / before : nil
        let comparisonVisible = hasPreviousCoverage
        let accent = theme.accent
        let periods = ar ? ["أسبوع", "شهر", "٣ أشهر", "سنة"] : ["W", "M", "3M", "Y"]
        let periodNames = ar ? ["أسبوع", "شهر", "٣ أشهر", "سنة"] : ["Week", "Month", "3 months", "Year"]
        let heading = selected.map { bucketLabel($0.start) }
            ?? selectedCategory.map { GhafLocalization.category($0, languageCode: lang) }
            ?? (ar ? "المصروف · \(periodNames[period.rawValue])" : "Spent · \(periodNames[period.rawValue])")
        return VStack(spacing: 8) {
            Text(heading)
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1).frame(height: 20)
            GhafRollingNumber(amount: Decimal(selected.map { $0.total + ($0.forecast ?? 0) } ?? spent), currency: currency, languageCode: lang, size: 40)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("stats.period.spent")
            Group {
            if let change, comparisonVisible, selected == nil, selectedCategory == nil {
                Label(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(Locale(identifier: lang)))
                      + (ar ? " عن الفترة السابقة" : " vs previous"),
                      systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(change > 0 ? theme.over : theme.credit)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((change > 0 ? theme.over : theme.credit).opacity(0.16), in: Capsule())
            } else {
                Text(selected != nil || selectedCategory != nil ? (ar ? "اضغط مرة أخرى لرؤية المجموع" : "Tap again for the total")
                                     : (ar ? "لا توجد بيانات للفترة السابقة" : "No data for the previous period"))
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.vertical, 5)
            }
            }
            .frame(height: 30)
            // Owner 1.31: a tapped point offers the transactions behind its number. The slot is always there
            // (hidden when nothing is selected) so the card never changes height.
            let items = selected.map { sel in current.filter { $0.date >= sel.start && $0.date < sel.end } } ?? []
            do {
                Button {
                    guard let selected else { return }
                    barTransactions = BarTransactions(title: bucketLabel(selected.start), items: items)
                } label: {
                    Label(ar ? "عرض العمليات" : "View transactions", systemImage: "list.bullet")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.ghafPress)
                .disabled(items.isEmpty)
                .opacity(selected == nil ? 0 : 1)
                .allowsHitTesting(selected != nil)
                .accessibilityHidden(selected == nil)
            }
            Chart {
                ForEach(plotted) { bucket in
                let isSelected = selected?.id == bucket.id
                let pointOpacity = isSelected ? 1.0 : 0.0
                RuleMark(x: .value("Date", chartKey(bucket.start)))
                    .foregroundStyle(theme.secondaryText.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    // Owner: the pill keeps one height (top of the chart) and only slides sideways.
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        selectionBubble(amount: bucket.total + (bucket.forecast ?? 0), date: bucket.start).opacity(isSelected ? 1 : 0)
                    }
                    .opacity(isSelected ? 1 : 0)
                if bucket.start <= GhafClock.now {
                    actualTrendMark(bucket)
                    PointMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total))
                        .symbol { Circle().fill(accent).frame(width: isSelected ? 10 : 0, height: isSelected ? 10 : 0) }
                        .foregroundStyle(accent.opacity(pointOpacity))
                        .opacity(pointOpacity)
                        .accessibilityLabel(bucketLabel(bucket.start))
                        .accessibilityValue(GhafFormat.shownMoney(Decimal(bucket.total), currency: currency, languageCode: lang))
                    if bucket.forecast == nil {
                        PointMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total))
                            .symbol {
                                Circle().fill(accent).frame(width: isSelected ? 10 : 0, height: isSelected ? 10 : 0)
                                    .overlay(Circle().stroke(theme.surface, lineWidth: isSelected ? 2 : 0))
                            }
                            .opacity(isSelected ? 1 : 0)
                    }
                }
            }
                ForEach(Array(forecastPoints.enumerated()), id: \.offset) { entry in
                    let (bucket, amount) = entry.element
                    AreaMark(x: .value("Date", chartKey(bucket.start)), yStart: .value("Baseline", 0), yEnd: .value(currency, amount), series: .value("Series", "Forecast"))
                        .foregroundStyle(accent.opacity(0.06))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, amount), series: .value("Series", "Forecast"))
                        .foregroundStyle(accent.opacity(theme.isDark ? 0.55 : 0.45))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4]))
                        .accessibilityLabel(ar ? "توقع · \(bucketLabel(bucket.start))" : "Forecast · \(bucketLabel(bucket.start))")
                        .accessibilityValue(GhafFormat.shownMoney(Decimal(amount), currency: currency, languageCode: lang))
                    if bucket.forecast != nil, selected?.id == bucket.id {
                        PointMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, amount))
                            .symbol { Circle().fill(accent).frame(width: 10, height: 10).overlay(Circle().stroke(theme.surface, lineWidth: 2)) }
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            // Fixed headroom: the curve never runs off the top and the pinned pill has room above the highest point.
            .chartYScale(domain: 0...max(1, (plotted.map(\.total) + forecastPoints.map(\.1)).max() ?? 1) * 1.3)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.28), value: period)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            guard let anchor = proxy.plotFrame else { selectedLabel = nil; return }
                            selectBucket(at: value.location, plotFrame: geometry[anchor], proxy: proxy, data: plotted)
                        })
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                            guard let anchor = proxy.plotFrame, let label: String = proxy.value(atX: value.location.x - geometry[anchor].minX) else { return }
                            // Short spring so the pill and dot glide between points while scrubbing, still tracking the finger.
                            guard label != selectedLabel else { return }
                            withAnimation(reduceMotion ? nil : .interactiveSpring(duration: 0.18)) { selectedLabel = label }
                        })
                }
            }
            .accessibilityRepresentation {
                VStack {
                    ForEach(plotted) { bucket in
                        Button {
                            tapTrendBucket(chartKey(bucket.start))
                        } label: { Text(bucketLabel(bucket.start)) }
                            .accessibilityValue(GhafFormat.shownMoney(Decimal(bucket.total + (bucket.forecast ?? 0)), currency: currency, languageCode: lang))
                            .accessibilityAddTraits(selected?.id == bucket.id ? .isSelected : [])
                    }
                }
            }
            .chartPlotStyle { plot in plot.padding(.horizontal, 8) }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(theme.outline.opacity(0.32))
                }
            }
            .chartXAxis {
                let labels: [String] = switch period {
                case .week: plotted.map { chartKey($0.start) }
                case .month, .quarter: groupWindows().compactMap { window in
                    // The middle plotted day of each group, so the centred label never clips and never vanishes.
                    let days = plotted.filter { $0.start >= window.start && $0.start < window.end }
                    return days.isEmpty ? nil : chartKey(days[days.count / 2].start)
                }
                case .year: plotted.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? chartKey($0.element.start) : nil }
                }
                let shown = Set(labels)
                AxisMarks(values: labels) { value in
                    AxisValueLabel(anchor: .top) {
                        // Owner #51: on device every day got a label (piling into a smear); draw only the chosen ones.
                        if let key = value.as(String.self), shown.contains(key), let bucket = plotted.first(where: { chartKey($0.start) == key }) {
                            Text(axisLabel(bucket.start)).font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.15), value: period)
                                .foregroundStyle(theme.secondaryText.opacity(bucket.start > GhafClock.now ? 0.75 : 1))
                        }
                    }
                }
            }
            .frame(height: 200)
            .padding(.top, 14)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(ar ? "اتجاه المصروف، اسحب لقراءة كل نقطة" : "Spending trend; drag to read each point")
            // Always laid out (hidden without a forecast) so the period picker below never moves.
            HStack(spacing: 6) {
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        context.stroke(path, with: .color(accent.opacity(theme.isDark ? 0.55 : 0.45)), style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    }
                    .frame(width: 16, height: 8)
                    Text(ar ? "توقع · بناءً على آخر ٩٠ يوماً" : "Forecast · based on your last 90 days")
                        .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .center)
                .opacity(all.contains(where: { $0.forecast != nil }) ? 1 : 0)
                .accessibilityHidden(!all.contains(where: { $0.forecast != nil }))

            GhafSegmented(options: Array(zip(Period.allCases, periods)), selection: $period, theme: theme, languageCode: lang)
                .scaleEffect(x: 1, y: 52.0 / 56.0)
                .frame(height: 52)
                .padding(.top, 8)
                .transaction { $0.animation = nil }
            .onChange(of: period) { _, _ in
                selectedLabel = nil
                selectedCategory = nil
                guard chartReady else { return }
                chartDrawProgress = 0
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.28)) { chartDrawProgress = 1 }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(GhafMetrics.heroPadding)
        .ghafStatsCard(theme: theme, radius: 30)
    }

    private func selectBucket(at location: CGPoint, plotFrame: CGRect, proxy: ChartProxy, data: [Bucket]) {
        let relativeX = location.x - plotFrame.minX
        let key: String? = proxy.value(atX: relativeX, as: String.self)
        guard let key, data.contains(where: { chartKey($0.start) == key }) else {
            withAnimation(.snappy) { selectedLabel = nil }
            return
        }
        tapTrendBucket(key)
    }

    private func tapTrendBucket(_ key: String) {
        // Select/unselect fades the dot, guide line and pill in or out instead of popping.
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.28)) { selectedLabel = selectedLabel == key ? nil : key }
    }

#if DEBUG
    private func runAutoSelection(scrollProxy: ScrollViewProxy) {
        let categories = slices(expenses(in: interval)).map(\.category)
        let target = GhafClock.now.addingTimeInterval(-2 * 86_400)
        let point = chartKey(bucketWindows().first(where: { $0.start <= target && target < $0.end })?.start ?? GhafClock.now)
        // The capture starts 1.5s after launch; the first view appears about 0.5s after launch.
        let actions: [(TimeInterval, () -> Void)] = [
            (2.0, { if categories.indices.contains(1) { toggle(categories[1]) } }),
            (3.0, { if categories.indices.contains(2) { toggle(categories[2]) } }),
            (4.0, { if categories.indices.contains(2) { toggle(categories[2]) } }),
            (5.0, { tapTrendBucket(point) }),
            (6.0, { tapTrendBucket(point) })
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { scrollProxy.scrollTo("category-chart", anchor: .center) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { scrollProxy.scrollTo("trend-chart", anchor: .top) }
        for (delay, action) in actions { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) }
    }
#endif

    private func selectionBubble(amount: Double, date: Date) -> some View {
        HStack(spacing: 4) {
            GhafMoneyLabel(amount: Decimal(amount), currency: currency, languageCode: lang, size: 15, weight: .semibold)
            Text("· \(bucketLabel(date))").font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
        }
        .foregroundStyle(theme.primaryText).padding(.horizontal, 10).padding(.vertical, 6)
        .background(theme.surface, in: Capsule())
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
            .padding(GhafMetrics.cardPadding)
            .ghafStatsCard(theme: theme, radius: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.ghafPress)
    }

    // MARK: Where it went

    /// Canvas "Where it went": the five biggest categories as tappable bars; a tap filters the hero line.
    private func whereItWent(_ data: [Slice], transferTotal: Decimal) -> some View {
        let top = Array(data.prefix(5))
        let most = top.first?.total ?? 1
        return VStack(spacing: 10) {
            VStack(alignment: .center, spacing: 3) {
                Text(ar ? "أين ذهب المال" : "Where it went")
                    .font(GhafTypography.heading(20, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                Text(ar ? "اضغط فئة للتصفية" : "Tap a category to filter")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            if top.isEmpty {
                Text(ar ? "لا يوجد صرف في هذه الفترة." : "No spending in this period.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .ghafEntrance(1)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(top.enumerated()), id: \.offset) { index, slice in
                        let on = selectedCategory == slice.category
                        Button { toggle(slice.category) } label: {
                            VStack(spacing: 12) {
                                Spacer(minLength: 0)
                                Text(GhafCompactNumber.string(slice.total, languageCode: lang))
                                    .font(GhafTypography.number(12, weight: .bold))
                                    .foregroundStyle(on ? theme.primaryText : theme.secondaryText)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(theme.accent.opacity(on ? 1 : selectedCategory == nil ? 0.85 : 0.3))
                                    .frame(height: max(10, 92 * slice.total / most) * chartDrawProgress)
                                    .animation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.28).delay(min(Double(index) * 0.015, 0.2)), value: chartDrawProgress)
                                Text(GhafLocalization.category(slice.category, languageCode: lang))
                                    .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(1).fixedSize(horizontal: false, vertical: false)
                                    .multilineTextAlignment(.center).minimumScaleFactor(0.82)
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
            if transferTotal > 0 {
                Button { toggle("Transfers") } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 36, height: 36)
                            .background(theme.accent.opacity(0.12), in: Circle())
                        Text(ar ? "تحويلات خارجية" : "Outgoing transfers")
                            .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        GhafMoneyLabel(amount: transferTotal, currency: currency, languageCode: lang, size: 14, weight: .semibold)
                            .foregroundStyle(theme.primaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 8)
                    .background(theme.accent.opacity(selectedCategory == "Transfers" ? 0.14 : 0.06),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ar ? "تحويلات خارجية" : "Outgoing transfers") \(GhafFormat.shownMoney(transferTotal, currency: currency, languageCode: lang))")
                .accessibilityAddTraits(selectedCategory == "Transfers" ? .isSelected : [])
            }
        }
        .padding(GhafMetrics.cardPadding)
        .ghafStatsCard(theme: theme, radius: 24)
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: lang)))
    }

    private func toggle(_ category: String) {
        withAnimation(.snappy) { selectedCategory = selectedCategory == category ? nil : category; selectedLabel = nil }
    }

    // MARK: Tiles and merchants

    private func tiles(_ items: [GhafTransaction]) -> some View {
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: min(GhafClock.now, interval.end)).day ?? 1)
        let units = ar ? ["هذا الأسبوع", "هذا الشهر", "آخر ٣ أشهر", "هذه السنة"] : ["this week", "this month", "these 3 months", "this year"]
        return HStack(spacing: 10) {
            VStack(spacing: 8) {
                Text(ar ? "متوسط اليوم" : "Daily average")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(GhafCompactNumber.string(total(items) / Double(days), languageCode: lang))
                    .contentTransition(.opacity)
                    .font(GhafTypography.number(28, weight: .heavy))
                    .foregroundStyle(theme.primaryText)
                Text(ar ? "\(currency) يومياً" : "\(currency) a day")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 96).padding(GhafMetrics.cardPadding)
            .ghafStatsCard(theme: theme, radius: 22)
            VStack(spacing: 8) {
                Text(ar ? "المشتريات" : "Purchases")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(items.count.formatted(.number.locale(Locale(identifier: lang))))
                    .font(GhafTypography.number(28, weight: .heavy))
                    .foregroundStyle(theme.primaryText)
                Text(units[period.rawValue])
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 96).padding(GhafMetrics.cardPadding)
            .ghafStatsCard(theme: theme, radius: 22)
        }
    }

    private func merchants(_ items: [GhafTransaction]) -> some View {
        let ranked = Dictionary(grouping: items.compactMap { item -> (String, GhafTransaction)? in
            guard let name = GhafMerchantAliasStore.displayName(item.rawMerchant ?? item.merchant) else { return nil }
            return (name, item)
        }, by: \.0)
        .map { name, rows in
            GhafMerchantSummary(name: name,
                                total: rows.reduce(Decimal.zero) { $0 + $1.1.spendingAmount },
                                count: rows.count,
                                category: rows.first?.1.category ?? "Other")
        }
        .sorted { $0.total > $1.total }
        let top = Array(ranked.prefix(3))
        return GhafProFeatureMask(isUnlocked: proUnlocked, theme: theme, languageCode: lang, action: { showProSheet = true }) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ar ? "أكثر المتاجر" : "Top merchants")
                    .font(GhafTypography.heading(18, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if ranked.count > 3 {
                    NavigationLink {
                        GhafTopMerchantsView(merchants: ranked, currency: currency, languageCode: lang, theme: theme)
                    } label: {
                        Text(ar ? "عرض الكل" : "See all")
                            .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if ranked.isEmpty {
                Text(ar ? "لا توجد متاجر في هذه الفترة." : "No merchants in this period.")
                    .font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
            }
            VStack(spacing: 0) {
                ForEach(top) { row in
                    GhafMerchantRankingRow(merchant: row, currency: currency, languageCode: lang,
                                           theme: theme, maximum: top.first?.total ?? 1)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
            .ghafStatsCard(theme: theme)
          }
    }

    private var proCard: some View {
        Button { showProSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(theme.accent).font(.system(size: 17, weight: .semibold))
                Text("Ghaf Pro").font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                Spacer()
                Image(systemName: ar ? "chevron.left" : "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ghafStatsCard(theme: theme, radius: 22)
    }
}
