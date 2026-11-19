import SwiftUI
import SwiftData
import Charts
import GhafCore

/// The Stats tab: spending over a chosen period, by time and by category, in the main currency.
/// Laid out like the approved canvas: trend hero, "Where it went" bars, two tiles, merchants.
struct GhafStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    let settings: GhafSettings

    enum Period: Int, CaseIterable { case week, month, quarter, year }

    @State private var period: Period = .month
    @State private var selectedLabel: String?
    @State private var selectedCategory: String?
    @State private var showPro = false
    @State private var showProSheet = false

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var currency: String { settings.currency }
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
        var cursor = period == .month ? interval.start : calendar.dateInterval(of: bucketUnit, for: interval.start)!.start
        while cursor < interval.end {
            starts.append(cursor)
            cursor = calendar.date(byAdding: period == .month ? .day : bucketUnit, value: period == .month ? 7 : 1, to: cursor)!
        }
        var sums = [Date: Double]()
        for item in items {
            let start: Date
            if period == .month {
                let dayOffset = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: item.date)).day ?? 0
                start = calendar.date(byAdding: .day, value: (dayOffset / 7) * 7, to: interval.start)!
            } else {
                guard let unitStart = calendar.dateInterval(of: bucketUnit, for: item.date)?.start else { continue }
                start = unitStart
            }
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
                                let trendBuckets = buckets(filtered)
                                AnyView(trendHero(trendBuckets, current: filtered, previous: previousFiltered).ghafEntrance(0)).id("trend-chart")
                                if period == .month, let selected = selectedLabel.flatMap({ key in trendBuckets.first { chartKey($0.start) == key } }) {
                                    AnyView(weekBreakdown(selected, transactions: filtered))
                                }
                                AnyView(whereItWent(slices(current)).ghafEntrance(1)).id("category-chart")
                                AnyView(tiles(current).ghafEntrance(2))
                                AnyView(budgetLink.ghafEntrance(3))
                                AnyView(merchants(current).ghafEntrance(4))
                                AnyView(proCard.ghafEntrance(5))
                            }
                            .ghafScreenPadding()
                            .padding(.top, 12)
                            .padding(.bottom, 30)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .ghafBackground(theme: theme)
                .toolbar(.hidden, for: .navigationBar)
                .sensoryFeedback(.selection, trigger: period)
                .sensoryFeedback(.selection, trigger: selectedCategory)
                .sheet(isPresented: $showProSheet) { GhafProSheet(settings: settings, feature: ("Advanced statistics", "الإحصائيات المتقدمة")).ghafDirection(settings.languageCode) }
                .onAppear {
                    if period == .month && selectedLabel == nil {
                        let month = calendar.dateInterval(of: .month, for: .now)!.start
                        let offset = ((calendar.component(.day, from: .now) - 1) / 7) * 7
                        selectedLabel = chartKey(calendar.date(byAdding: .day, value: offset, to: month)!)
                    }
#if DEBUG
                guard GhafScreenshotFixture.enabled else { return }
                switch GhafScreenshotFixture.period {
                case "W": period = .week
                case "3M": period = .quarter
                case "Y": period = .year
                default: break
                }
                if GhafScreenshotFixture.destination == "pro-popup" { showPro = true }
                if GhafScreenshotFixture.destination == "pro-sheet" { showProSheet = true }
                if GhafScreenshotFixture.selection == "point" {
                    let date = calendar.dateInterval(of: .day, for: Date.now.addingTimeInterval(-9 * 86_400))?.start ?? .now
                    selectedLabel = chartKey(period == .month ? calendar.date(byAdding: .day, value: (((calendar.component(.day, from: date) - 1) / 7) * 7) + 1 - calendar.component(.day, from: date), to: date)! : date)
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
        .overlay { if showPro { proPopup.zIndex(2) } }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    // MARK: Trend hero

    /// Short, unique label for a bucket on the chart's axis.
    private func axisLabel(_ date: Date) -> String {
        let locale = Locale(identifier: lang)
        switch period {
        case .week: return date.formatted(.dateTime.weekday(.narrow).locale(locale))
        case .month:
            let first = calendar.component(.day, from: date)
            let lastDate = min(calendar.date(byAdding: .day, value: 6, to: date)!, interval.end.addingTimeInterval(-1))
            return "\(first)–\(calendar.component(.day, from: lastDate))"
        case .quarter: return date.formatted(.dateTime.month(.abbreviated).locale(locale))
        case .year: return date.formatted(.dateTime.month(.abbreviated).locale(locale))
        }
    }

    private func chartKey(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }

    private func bucketLabel(_ date: Date) -> String {
        let locale = Locale(identifier: lang)
        if period == .month {
            let last = min(calendar.date(byAdding: .day, value: 6, to: date)!, interval.end.addingTimeInterval(-1))
            return "\(date.formatted(.dateTime.day().locale(locale)))–\(last.formatted(.dateTime.day().locale(locale))) \(last.formatted(.dateTime.month(.abbreviated).locale(locale)))"
        }
        switch period {
        case .week: return date.formatted(.dateTime.weekday(.wide).locale(locale))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        case .quarter: return date.formatted(.dateTime.month(.wide).locale(locale))
        case .year: return date.formatted(.dateTime.month(.wide).locale(locale))
        }
    }

    /// One card in the theme's surface, Stocks style: the total (or the scrubbed point), the change against the previous
    /// period, a line you drag across, and the period chips under it. Every value comes from the ledger.
    private func trendHero(_ all: [Bucket], current: [GhafTransaction], previous: [GhafTransaction]) -> some View {
        // Days that haven't happened yet aren't zero spending: the line stops at today, like Stocks.
        let data = all
        let plotted = all.filter { $0.start <= .now }
        // Plotted by a short label per bucket, not by date: date-unit marks by week or month crash Charts (NaN).
        let selected = selectedLabel.flatMap { key in plotted.first { chartKey($0.start) == key } }
        let spent = total(current)
        let before = total(previous)
        let change = before > 0 ? (spent - before) / before : nil
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
                .contentTransition(.opacity)
            GhafMoneyLabel(amount: Decimal(selected?.total ?? spent), currency: currency, languageCode: lang, size: 40)
                .foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
                .environment(\.layoutDirection, .leftToRight)
            if let change, selected == nil, selectedCategory == nil {
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
            Chart(plotted) { bucket in
                AreaMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                    .symbolSize(0)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                let isSelected = selected?.id == bucket.id
                let pointOpacity = isSelected ? 1.0 : 0.0
                PointMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total))
                    .symbol {
                        Circle().fill(accent.opacity(pointOpacity))
                            .frame(width: isSelected ? 10 : 0, height: isSelected ? 10 : 0)
                    }
                    .foregroundStyle(accent.opacity(pointOpacity))
                    .opacity(pointOpacity)
                    .accessibilityLabel(bucketLabel(bucket.start))
                    .accessibilityValue(GhafFormat.shownMoney(Decimal(bucket.total), currency: currency, languageCode: lang))
                RuleMark(x: .value("Date", chartKey(bucket.start)))
                    .foregroundStyle(theme.secondaryText.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .opacity(isSelected ? 1 : 0)
                PointMark(x: .value("Date", chartKey(bucket.start)), y: .value(currency, bucket.total))
                    .symbol {
                        Circle().fill(accent).frame(width: isSelected ? 10 : 0, height: isSelected ? 10 : 0)
                            .overlay(Circle().stroke(theme.surface, lineWidth: isSelected ? 2 : 0))
                    }
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionBubble(amount: bucket.total, date: bucket.start).opacity(isSelected ? 1 : 0)
                    }
                    .opacity(isSelected ? 1 : 0)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            guard let anchor = proxy.plotFrame else { selectedLabel = nil; return }
                            selectBucket(at: value.location, plotFrame: geometry[anchor], proxy: proxy, data: data)
                        })
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                            guard let anchor = proxy.plotFrame, let label: String = proxy.value(atX: value.location.x - geometry[anchor].minX) else { return }
                            selectedLabel = label
                        })
                }
            }
            .accessibilityRepresentation {
                VStack {
                    ForEach(data) { bucket in
                        Button {
                            tapTrendBucket(chartKey(bucket.start))
                        } label: { Text(bucketLabel(bucket.start)) }
                            .accessibilityValue(GhafFormat.shownMoney(Decimal(bucket.total), currency: currency, languageCode: lang))
                            .accessibilityAddTraits(selected?.id == bucket.id ? .isSelected : [])
                    }
                }
            }
            // A new chart per period, faded in: Charts animating between different label sets produces NaN geometry.
            .id(period)
            .transition(.opacity)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(theme.outline.opacity(0.32))
                }
            }
            .chartXAxis {
                AxisMarks(values: data.map { chartKey($0.start) }) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self), let bucket = data.first(where: { chartKey($0.start) == key }) {
                            Text(axisLabel(bucket.start)).font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                                .foregroundStyle(theme.secondaryText.opacity(bucket.start > .now ? 0.4 : 1))
                        }
                    }
                }
            }
            .frame(height: 200)
            .padding(.top, 14)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(ar ? "اتجاه الصرف، اسحب لقراءة كل نقطة" : "Spending trend; drag to read each point")

            GhafSegmented(options: Array(zip(Period.allCases, periods)), selection: $period, theme: theme, languageCode: lang)
                .scaleEffect(x: 1, y: 52.0 / 56.0)
                .frame(height: 52)
                .padding(.top, 8)
            .onChange(of: period) { _, value in
                selectedLabel = nil
                selectedCategory = nil
                if value == .month {
                    let month = calendar.dateInterval(of: .month, for: .now)!.start
                    let offset = ((calendar.component(.day, from: .now) - 1) / 7) * 7
                    selectedLabel = chartKey(calendar.date(byAdding: .day, value: offset, to: month)!)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(GhafMetrics.heroPadding)
        .ghafStatsCard(theme: theme, radius: 30)
    }

    private func selectBucket(at location: CGPoint, plotFrame: CGRect, proxy: ChartProxy, data: [Bucket]) {
        let relativeX = location.x - plotFrame.minX
        let key: String? = proxy.value(atX: relativeX, as: String.self)
        guard let key, let bucket = data.first(where: { chartKey($0.start) == key }),
              let pointX = proxy.position(forX: key), let pointY = proxy.position(forY: bucket.total) else {
            withAnimation(.snappy) { selectedLabel = nil }
            return
        }
        let dx = location.x - plotFrame.minX - pointX
        let dy = location.y - plotFrame.minY - pointY
        guard dx * dx + dy * dy < 784 else { withAnimation(.snappy) { selectedLabel = nil }; return }
        tapTrendBucket(key)
    }

    private func tapTrendBucket(_ key: String) {
        selectedLabel = selectedLabel == key ? nil : key
    }

    private func weekBreakdown(_ bucket: Bucket, transactions: [GhafTransaction]) -> some View {
        let days = (0..<7).compactMap { offset -> (Date, Decimal)? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: bucket.start), date < interval.end, date <= .now else { return nil }
            let amount = transactions.filter { calendar.isDate($0.date, inSameDayAs: date) }
                .reduce(Decimal.zero) { $0 + $1.spendingAmount }
            return (date, amount)
        }
        let maximum = max(1, days.map { NSDecimalNumber(decimal: $0.1).doubleValue }.max() ?? 0)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days, id: \.0) { date, amount in
                VStack(spacing: 4) {
                    Text(GhafCompactNumber.string(NSDecimalNumber(decimal: amount).doubleValue, languageCode: lang))
                        .font(GhafTypography.body(9, languageCode: lang)).foregroundStyle(theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                    Capsule().fill(theme.accent.opacity(0.6))
                        .frame(height: max(4, 34 * NSDecimalNumber(decimal: amount).doubleValue / maximum))
                    Text(date.formatted(.dateTime.day().locale(Locale(identifier: lang))))
                        .font(GhafTypography.body(10, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityLabel(ar ? "تفصيل المصروف اليومي لهذا الأسبوع" : "Daily spending breakdown for this week")
    }

#if DEBUG
    private func runAutoSelection(scrollProxy: ScrollViewProxy) {
        let categories = slices(expenses(in: interval)).map(\.category)
        let point = chartKey(calendar.dateInterval(of: bucketUnit, for: Date.now.addingTimeInterval(-2 * 86_400))?.start ?? .now)
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
        }
        .buttonStyle(.ghafPress)
    }

    // MARK: Where it went

    /// Canvas "Where it went": the five biggest categories as tappable bars; a tap filters the hero line.
    private func whereItWent(_ data: [Slice]) -> some View {
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
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(top) { slice in
                        let on = selectedCategory == slice.category
                        Button { toggle(slice.category) } label: {
                            VStack(spacing: 12) {
                                Spacer(minLength: 0)
                                Text(GhafCompactNumber.string(slice.total, languageCode: lang))
                                    .font(GhafTypography.number(11, weight: .bold))
                                    .foregroundStyle(on ? theme.primaryText : theme.secondaryText)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(GhafCategoryIcon.chartColor(slice.category, dark: theme.isDark).opacity(on ? 1 : selectedCategory == nil ? 0.85 : 0.3))
                                    .frame(height: max(10, 92 * slice.total / most))
                                Text(GhafLocalization.category(slice.category, languageCode: lang))
                                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
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
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: min(Date.now, interval.end)).day ?? 1)
        let units = ar ? ["هذا الأسبوع", "هذا الشهر", "آخر ٣ أشهر", "هذه السنة"] : ["this week", "this month", "these 3 months", "this year"]
        return HStack(spacing: 10) {
            VStack(spacing: 8) {
                Text(ar ? "متوسط اليوم" : "Daily average")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.accentContrast.opacity(0.65))
                Text(GhafCompactNumber.string(total(items) / Double(days), languageCode: lang))
                    .contentTransition(.opacity)
                    .font(GhafTypography.number(28, weight: .heavy))
                    .foregroundStyle(theme.accentContrast)
                Text(ar ? "\(currency) يومياً" : "\(currency) a day")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.accentContrast.opacity(0.65))
            }
            .frame(maxWidth: .infinity, minHeight: 96).padding(GhafMetrics.cardPadding)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        .ghafStatsCard(theme: theme)
    }

    private var proCard: some View {
        Button { showPro = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                Text("Ghaf Pro").font(GhafTypography.body(14, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                Image(systemName: ar ? "chevron.left" : "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var proPopup: some View {
        ZStack {
            theme.background.opacity(0.55).ignoresSafeArea().onTapGesture { closePro() }
            VStack(spacing: 0) {
                HStack {
                    Text("Pro").font(GhafTypography.body(13, languageCode: lang, weight: .bold)).foregroundStyle(theme.accentContrast).padding(.horizontal, 12).padding(.vertical, 7).background(theme.accent, in: Capsule())
                    Spacer()
                    Button { closePro() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.primaryText).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel(ar ? "إغلاق" : "Close")
                }
                Image(systemName: "sparkles").font(.system(size: 28, weight: .bold)).foregroundStyle(theme.accentContrast)
                    .frame(width: 64, height: 64).background(theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).padding(.top, 24)
                Text(ar ? "الترقية إلى Pro" : "Upgrade to Pro").font(GhafTypography.display(26, languageCode: lang)).foregroundStyle(theme.primaryText).multilineTextAlignment(.center).padding(.top, 24)
                Text(ar ? "تقارير أعمق، ودجت، ونشاط مباشر" : "Deeper reports, widgets and Live Activities").font(GhafTypography.body(17, languageCode: lang)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center).padding(.top, 8)
                Button { showPro = false; showProSheet = true } label: {
                    Text(ar ? "عرض الخطط ←" : "See plans →").font(GhafTypography.body(17, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.surface).frame(maxWidth: .infinity, minHeight: 56)
                        .background(theme.primaryText, in: Capsule())
                }.buttonStyle(.plain).padding(.top, 24)
                Text(ar ? "لا توجد دفعة حقيقية في هذا الإصدار." : "This build does not take a real payment.")
                    .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center).padding(.top, 16)
            }
            .padding(24).frame(maxWidth: 360).background(theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: showPro)
    }

    private func closePro() {
        if reduceMotion { showPro = false } else { withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { showPro = false } }
    }
}
