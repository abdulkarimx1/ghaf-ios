import SwiftUI
import SwiftData
import Charts
import GhafCore

/// Budget, laid out like the approved canvas: salary header, 50/30/20 auto-allocation,
/// pace against plan, and six months of spending. Every number comes from the ledger and Settings.
struct GhafBudgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    let settings: GhafSettings

    @State private var bucket: BudgetAllocation.Bucket = .needs
    @State private var bucketSelected = false
    @State private var selectedMonth: Date?

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var currency: String { settings.currency }
    private var calendar: Calendar { GhafCalendar.current }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }
    private var hasSalary: Bool { settings.salaryEnabled == true && settings.salaryDay != nil }

    /// Income for the budget period: the salary when it's set up, else the monthly income from Settings.
    private var income: Decimal {
        settings.salaryEnabled == true ? (settings.salaryAmount ?? settings.monthlyIncome) : settings.monthlyIncome
    }

    /// The salary cycle when a salary day is set, else this calendar month (same rule as BudgetCalculator).
    private var cycle: DateInterval {
        if hasSalary, let day = settings.salaryDay {
            let start = GhafSalaryCycle.startDate(for: .now, salaryDay: day)
            return DateInterval(start: start, end: GhafSalaryCycle.nextSalaryDate(after: .now, salaryDay: day))
        }
        return calendar.dateInterval(of: .month, for: .now)!
    }

    private func expenses(in range: DateInterval) -> [GhafTransaction] {
        transactions.filter { $0.currency == currency && $0.isExpense && range.contains($0.date) }
    }

    var body: some View {
        let spending = expenses(in: cycle)
        let needs = spent(.needs, spending), wants = spent(.wants, spending)
        ScrollView {
            VStack(spacing: 12) {
                // Erased sections: deep view types overflow the stack on iOS 27.
                AnyView(header)
                AnyView(allocationCard(needs: needs, wants: wants))
                if income > 0 { AnyView(paceRow(needs: needs, wants: wants)) }
                AnyView(trendCard)
            }
            .ghafScreenPadding()
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ghafBackground(theme: theme)
        .navigationTitle(ar ? "الميزانية" : "Budget")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: bucket)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private func spent(_ bucket: BudgetAllocation.Bucket, _ items: [GhafTransaction]) -> Decimal {
        items.filter { BudgetAllocation.bucket(forCategory: $0.category) == bucket }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
    }

    // MARK: Header

    private var header: some View {
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: cycle.end).day ?? 0)
        let started = cycle.start.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: lang)))
        let detail = hasSalary
            ? (ar ? "بدأت الدورة \(started) · \(days) يوم للراتب القادم" : "Cycle started \(started) · \(days) days to next salary")
            : (ar ? "هذا الشهر · بقي \(days) يوم" : "This month · \(days) days left")
        return VStack(spacing: 2) {
            Text(hasSalary ? (ar ? "الراتب الشهري" : "Monthly salary") : (ar ? "الدخل الشهري" : "Monthly income"))
                .font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            GhafMoneyLabel(amount: income, currency: currency, languageCode: lang, size: 36)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
            Text(detail)
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: Auto-allocation

    private func allocationCard(needs: Decimal, wants: Decimal) -> some View {
        let names = ar ? ["الأساسيات", "الرغبات", "الادخار"] : ["Needs", "Wants", "Savings"]
        let notes = ar ? ["إيجار، فواتير، بقالة، سيارة", "مطاعم، تسوق، ترفيه", "ما يبقى من دخلك"]
                       : ["Rent, bills, groceries, car", "Dining, shopping, fun", "What's left of your income"]
        let colors = [theme.accent, theme.glow, theme.credit]
        let planned = bucketSelected ? income * BudgetAllocation.share(bucket) : income
        let used: Decimal = bucketSelected ? (bucket == .needs ? needs : bucket == .wants ? wants : max(income - needs - wants, 0)) : needs + wants
        let ratio = planned > 0 ? min(max(NSDecimalNumber(decimal: used / planned).doubleValue, 0), 1.5) : 0
        let activeName = bucketSelected ? names[bucket.rawValue] : (ar ? "الإجمالي" : "Total")
        let activeColor = bucketSelected ? colors[bucket.rawValue] : theme.accent
        let allocationSelection = Binding<BudgetAllocation.Bucket>(
            get: { bucket },
            set: { value in
                withAnimation(.snappy) {
                    if bucket == value && bucketSelected { bucketSelected = false }
                    else { bucket = value; bucketSelected = true }
                }
            }
        )
        return VStack(spacing: 14) {
            Text(ar ? "التوزيع التلقائي" : "Auto-allocation")
                .font(GhafTypography.body(15, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.secondaryText)
            if income <= 0 {
                Text(ar ? "أضف دخلك الشهري من المزيد › الميزانية والفئات، أو راتبك من دورة الراتب، ليقسّمه غاف ٥٠/٣٠/٢٠."
                        : "Add your monthly income in More › Budget & categories, or your salary in Salary cycle, and Ghaf splits it 50/30/20.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                ZStack {
                Chart(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                    SectorMark(angle: .value("Share", NSDecimalNumber(decimal: BudgetAllocation.share(item)).doubleValue),
                               innerRadius: .ratio(0.62), outerRadius: .ratio(1), angularInset: 2)
                        .foregroundStyle(colors[item.rawValue])
                        .opacity(!bucketSelected || item == bucket ? 1 : 0.3)
                        .accessibilityLabel(names[item.rawValue])
                        .accessibilityValue(GhafFormat.shownMoney(income * BudgetAllocation.share(item), currency: currency, languageCode: lang))
                    if bucketSelected && item == bucket {
                        SectorMark(angle: .value("Selected share", NSDecimalNumber(decimal: BudgetAllocation.share(item)).doubleValue),
                                   innerRadius: .ratio(0.95), outerRadius: .ratio(1), angularInset: 2)
                            .foregroundStyle(theme.primaryText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 200, height: 200)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { tap in
                                guard let anchor = proxy.plotFrame else { return }
                                let frame = geometry[anchor]
                                let point = CGPoint(x: tap.location.x - frame.midX, y: tap.location.y - frame.midY)
                                let radius = hypot(point.x, point.y)
                                guard radius > 62 && radius < 100 else { withAnimation(.snappy) { bucketSelected = false }; return }
                                let degrees = (atan2(point.x, -point.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                                let values = BudgetAllocation.Bucket.allCases.map { NSDecimalNumber(decimal: BudgetAllocation.share($0)).doubleValue * 360 }
                                var edge = 0.0
                                for (index, amount) in values.enumerated() {
                                    if degrees >= edge && degrees < edge + amount {
                                        withAnimation(.snappy) {
                                            let chosen = BudgetAllocation.Bucket.allCases[index]
                                            if chosen == bucket && bucketSelected { bucketSelected = false }
                                            else { bucket = chosen; bucketSelected = true }
                                        }
                                        break
                                    }
                                    edge += amount
                                }
                            })
                    }
                }
                .accessibilityRepresentation {
                    VStack {
                        ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                            Button {
                                withAnimation(.snappy) {
                                    if bucketSelected && bucket == item { bucketSelected = false }
                                    else { bucket = item; bucketSelected = true }
                                }
                            } label: { Text(names[item.rawValue]) }
                                .accessibilityValue(GhafFormat.shownMoney(income * BudgetAllocation.share(item), currency: currency, languageCode: lang))
                                .accessibilityAddTraits(bucketSelected && item == bucket ? .isSelected : [])
                        }
                    }
                }
                VStack(spacing: 8) {
                    Text(bucketSelected ? NSDecimalNumber(decimal: BudgetAllocation.share(bucket) * 100).stringValue + "%" : "100%")
                        .font(GhafTypography.number(28, weight: .heavy)).foregroundStyle(theme.primaryText)
                    Text(activeName).font(GhafTypography.body(13, languageCode: lang, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 15).foregroundStyle(theme.primaryText)
                }
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
                }
                .accessibilityElement(children: .contain)

                GhafSegmented(options: Array(zip(BudgetAllocation.Bucket.allCases, names)), selection: allocationSelection, theme: theme, languageCode: lang)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                        Button { withAnimation(.snappy) { if bucket == item && bucketSelected { bucketSelected = false } else { bucket = item; bucketSelected = true } } } label: {
                            VStack(spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(colors[item.rawValue]).frame(width: 8, height: 8)
                                    Text(names[item.rawValue]).lineLimit(1)
                                    Text("\(Int(truncating: (BudgetAllocation.share(item) * 100) as NSNumber))%")
                                }
                                Text(GhafFormat.shownMoney(income * BudgetAllocation.share(item), currency: currency, languageCode: lang)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .accessibilityLabel("\(names[item.rawValue]), \(GhafFormat.shownMoney(income * BudgetAllocation.share(item), currency: currency, languageCode: lang))")
                        .accessibilityAddTraits(bucketSelected && bucket == item ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeName).font(GhafTypography.body(16, languageCode: lang, weight: .bold)).foregroundStyle(theme.primaryText)
                            Text(bucketSelected ? notes[bucket.rawValue] : (ar ? "الدخل مقابل المصروفات" : "Income and spending overview")).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 18)
                            .foregroundStyle(theme.primaryText).environment(\.layoutDirection, .leftToRight)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.elevatedSurface)
                            Capsule().fill(bucketSelected && bucket != .savings && ratio > 1 ? theme.over : activeColor)
                                .frame(width: max(6, proxy.size.width * min(ratio, 1)))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(bucketSelected && bucket == .savings
                             ? (ar ? "ادّخرت حتى الآن " : "Saved so far ") + GhafFormat.shownMoney(used, currency: currency, languageCode: lang)
                             : GhafFormat.shownMoney(max(planned - used, 0), currency: currency, languageCode: lang) + (ar ? " متبقٍ" : " left"))
                        Spacer()
                        Text(ratio.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: lang))) + (ar ? " مستخدم" : " used"))
                    }
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                }
                .padding(GhafMetrics.cardPadding)
                .ghafStatsCard(theme: theme, radius: 18)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .ghafStatsCard(theme: theme, radius: 28)
    }

    // MARK: Pace

    /// Spending so far in needs and wants against the 80% plan, prorated to today.
    private func paceRow(needs: Decimal, wants: Decimal) -> some View {
        let elapsed = min(max(Date.now.timeIntervalSince(cycle.start) / cycle.duration, 0.03), 1)
        let expected = NSDecimalNumber(decimal: income * 0.8).doubleValue * elapsed
        let actual = NSDecimalNumber(decimal: needs + wants).doubleValue
        let pace = expected > 0 ? (actual - expected) / expected : 0
        let percent = Int((abs(pace) * 100).rounded())
        let day = (calendar.dateComponents([.day], from: cycle.start, to: .now).day ?? 0) + 1
        let length = max(1, calendar.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? 30)
        let under = pace <= 0
        return NavigationLink { GhafSalarySettingsView(settings: settings) } label: {
            HStack(spacing: 12) {
                Image(systemName: under ? "checkmark" : "exclamationmark")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(under ? theme.credit : theme.over, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(under ? (ar ? "أقل من الخطة بـ \(percent)٪" : "You're \(percent)% under plan")
                               : (ar ? "أعلى من الخطة بـ \(percent)٪" : "You're \(percent)% over plan"))
                        .font(GhafTypography.body(15, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text(ar ? "اليوم \(day) من \(length) في هذه الدورة" : "Day \(day) of \(length) in this cycle")
                        .font(GhafTypography.body(13, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 4)
                Image(systemName: ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }
            .padding(GhafMetrics.cardPadding)
            .ghafStatsCard(theme: theme, radius: 22)
        }
        .buttonStyle(.ghafPress)
        .accessibilityHint(ar ? "يفتح إعدادات دورة الراتب" : "Opens salary cycle settings")
    }

    // MARK: Six-month trend

    private var trendCard: some View {
        let thisMonth = calendar.dateInterval(of: .month, for: .now)!
        let months: [(start: Date, total: Double)] = (0..<6).reversed().map { back in
            let start = calendar.date(byAdding: .month, value: -back, to: thisMonth.start)!
            let range = calendar.dateInterval(of: .month, for: start)!
            let sum = expenses(in: range).reduce(Decimal.zero) { $0 + $1.spendingAmount }
            return (start, NSDecimalNumber(decimal: sum).doubleValue)
        }
        let most = max(months.map(\.total).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(ar ? "اتجاه الصرف" : "Spending trend")
                .font(GhafTypography.body(15, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.primaryText)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(months, id: \.start) { month in
                    let current = month.start == thisMonth.start
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(current ? theme.accent : theme.primaryText.opacity(0.22))
                            .frame(height: max(6, 70 * month.total / most))
                        Text(month.start.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: lang))))
                            .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                            .foregroundStyle(current ? theme.primaryText : theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(month.start.formatted(.dateTime.month(.wide).locale(Locale(identifier: lang)))
                                        + " " + GhafFormat.shownMoney(Decimal(month.total), currency: currency, languageCode: lang))
                }
            }
        }
            .padding(GhafMetrics.cardPadding)
        .ghafCard(theme: theme, radius: 22)
    }
}
