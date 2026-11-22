import SwiftUI
import SwiftData
import Charts
import GhafCore

private struct EditCategory: Identifiable { let name: String; var id: String { name } }

/// Budget, laid out like the approved canvas: salary header, 50/30/20 auto-allocation,
/// pace against plan, and six months of spending. Every number comes from the ledger and Settings.
struct GhafBudgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \GhafTransaction.date, order: .reverse) private var transactions: [GhafTransaction]
    let settings: GhafSettings

    @State private var bucket: BudgetAllocation.Bucket = .needs
    @State private var bucketSelected = false
    @State private var selectedMonth: Date?
    @State private var selectedCategory: String?
    @State private var editingCategory: String?
    @State private var budgetEntry = ""
    @State private var showPresetSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var currency: String { settings.currency }
    private var calendar: Calendar { GhafCalendar.current }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }
    private var hasSalary: Bool { settings.salaryEnabled == true && settings.salaryDay != nil }
    private var preset: BudgetAllocation.Preset { BudgetAllocation.Preset(rawValue: settings.allocationPresetRaw) ?? .balanced }

    /// Income for the budget period: the salary when it's set up, else the monthly income from Settings.
    private var income: Decimal {
        settings.salaryEnabled == true ? (settings.salaryAmount ?? settings.monthlyIncome) : settings.monthlyIncome
    }
    private var incomeCurrency: String {
        settings.salaryEnabled == true ? (settings.salaryCurrency ?? settings.currency) : settings.currency
    }
    private var salaryCurrencyMismatch: Bool { hasSalary && incomeCurrency != currency }
    private var allocationIncome: Decimal { salaryCurrencyMismatch ? settings.monthlyIncome : income }

    /// The salary cycle when a salary day is set, else this calendar month (same rule as BudgetCalculator).
    private var cycle: DateInterval {
        if hasSalary, let day = settings.salaryDay {
            let start = GhafSalaryCycle.startDate(for: .now, salaryDay: day)
            return DateInterval(start: start, end: GhafSalaryCycle.nextSalaryDate(after: .now, salaryDay: day))
        }
        return calendar.dateInterval(of: .month, for: .now)!
    }

    private func expenses(in range: DateInterval) -> [GhafTransaction] {
        transactions.filter { transaction in
            guard transaction.currency == currency, transaction.isExpense, range.contains(transaction.date) else { return false }
            return !CategoryTaxonomy.isTransferOrAdjustment(category: transaction.category, subcategory: transaction.subcategory)
                && CategoryTaxonomy.category(named: transaction.category)?.isIncome != true
        }
    }

    var body: some View {
        let spending = expenses(in: cycle)
        let needs = spent(.needs, spending), wants = spent(.wants, spending)
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(spacing: 12) {
                // Erased sections: deep view types overflow the stack on iOS 27.
                AnyView(header)
                AnyView(petalBudgetCard)
                AnyView(allocationCard(needs: needs, wants: wants))
                if income > 0 { AnyView(paceRow(needs: needs, wants: wants)) }
                AnyView(trendCard).id("month-trend")
            }
            .ghafScreenPadding()
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ghafStatusBarFade(theme: theme)
        .ghafBackground(theme: theme)
        .navigationTitle(ar ? "الميزانية" : "Budget")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: bucket)
        .sensoryFeedback(.selection, trigger: bucketSelected)
        .sensoryFeedback(.selection, trigger: selectedMonth)
        .sheet(isPresented: $showPresetSheet) { presetSheet.presentationDetents([.height(430)]).presentationCornerRadius(32) }
        .sheet(item: Binding(get: { editingCategory.map(EditCategory.init) }, set: { editingCategory = $0?.name })) { item in
            budgetEditor(item.name).presentationDetents([.height(320)]).presentationCornerRadius(32)
        }
        .onAppear {
#if DEBUG
            guard GhafScreenshotFixture.enabled else { return }
            if GhafScreenshotFixture.screen == "budget-salary-currency" {
                settings.salaryEnabled = true
                settings.salaryDay = settings.salaryDay ?? 10
                settings.salaryAmount = settings.salaryAmount ?? 6000
                settings.salaryCurrency = "SAR"
                if settings.monthlyIncome <= 0 { settings.monthlyIncome = 12000 }
            }
            if GhafScreenshotFixture.selection == "wants" { bucket = .wants; bucketSelected = true }
            if GhafScreenshotFixture.selection == "savings" { bucket = .savings; bucketSelected = true }
            if GhafScreenshotFixture.selection == "petal" { selectedCategory = "Dining" }
            if GhafScreenshotFixture.selection == "over" {
                var budgets = settings.categoryBudgets; budgets["Subscriptions"] = 1; settings.categoryBudgets = budgets
            }
            if GhafScreenshotFixture.selection == "preset" { showPresetSheet = true }
            if GhafScreenshotFixture.selection == "edit-budget", let category = monthlySpendByCategory.first?.name {
                editingCategory = category; budgetEntry = NSDecimalNumber(decimal: monthlySpendByCategory.first?.budget ?? 0).stringValue
            }
            if GhafScreenshotFixture.selection == "month" {
                selectedMonth = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: .now)!.start)
            }
            if GhafScreenshotFixture.autoSelect { runAutoSelection(scrollProxy: scrollProxy) }
            if GhafScreenshotFixture.selection == "month" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scrollProxy.scrollTo("month-trend", anchor: .center) }
            }

#endif
}
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private func spent(_ bucket: BudgetAllocation.Bucket, _ items: [GhafTransaction]) -> Decimal {
        items.filter { BudgetAllocation.bucket(forCategory: $0.category) == bucket }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
    }

    private func toggleBucket(_ value: BudgetAllocation.Bucket) {
        withAnimation(.snappy) {
            if bucket == value && bucketSelected { bucketSelected = false }
            else { bucket = value; bucketSelected = true }
        }
    }

    private func toggleMonth(_ date: Date) {
        withAnimation(.snappy) { selectedMonth = selectedMonth == date ? nil : date }
    }

    private var monthlySpendByCategory: [(name: String, spent: Decimal, budget: Decimal)] {
        let totals = Dictionary(grouping: expenses(in: cycle), by: \.category)
            .mapValues { $0.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
        let historyStart = calendar.date(byAdding: .month, value: -3, to: cycle.start)!
        let history = Dictionary(grouping: expenses(in: DateInterval(start: historyStart, end: cycle.start)), by: \.category)
            .mapValues { $0.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
        let incomeOnly = Set(transactions.filter(\.isIncome).map(\.category)).subtracting(totals.keys)
        let names = Set(settings.categories).union(totals.keys).filter {
            !CategoryTaxonomy.isTransferOrAdjustment(category: $0, subcategory: nil)
                && CategoryTaxonomy.category(named: $0)?.isIncome != true
                && !incomeOnly.contains($0)
                && (CategoryTaxonomy.category(named: $0) != nil || CategoryTaxonomy.defaultNames.contains($0)
                    || totals[$0] != nil || history[$0] != nil || settings.categoryBudgets[$0] != nil)
        }
        return names.compactMap { name in
            let spent = totals[name, default: 0]
            return (name, spent, settings.categoryBudgets[name] ?? suggestedBudget(for: name, categories: Set(names), history: history))
        }.sorted { lhs, rhs in
            lhs.budget == rhs.budget ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : lhs.budget > rhs.budget
        }
    }

    private func suggestedBudget(for name: String, categories: Set<String>, history: [String: Decimal]) -> Decimal {
        let bucket = BudgetAllocation.bucket(forCategory: name)
        let bucketAmount = allocationIncome * preset.share(bucket)
        let historyTotal = categories.filter { BudgetAllocation.bucket(forCategory: $0) == bucket }.reduce(Decimal.zero) { $0 + history[$1, default: 0] }
        let bucketCategories = max(1, categories.filter { BudgetAllocation.bucket(forCategory: $0) == bucket }.count)
        return roundedBudget(historyTotal > 0 ? bucketAmount * history[name, default: 0] / historyTotal : bucketAmount / Decimal(bucketCategories))
    }

    private func roundedBudget(_ amount: Decimal) -> Decimal {
        var result = Decimal.zero, value = amount
        NSDecimalRound(&result, &value, GhafCurrencyDigits.fractionDigits(for: currency), .plain)
        return result
    }

    private var petalBudgetCard: some View {
        let rows = monthlySpendByCategory
        let all = rows.filter { $0.budget > 0 }
        let grouped = all.count > 7
        let shown = Array(all.prefix(grouped ? 6 : 7)) + (grouped ? [(name: ar ? "أخرى" : "Other", spent: all.dropFirst(6).reduce(Decimal.zero) { $0 + $1.spent }, budget: all.dropFirst(6).reduce(Decimal.zero) { $0 + $1.budget })] : [])
        let totalSpent = shown.reduce(Decimal.zero) { $0 + $1.spent }
        let totalBudget = shown.reduce(Decimal.zero) { $0 + $1.budget }
        let largestBudget = shown.map(\.budget).max() ?? .zero
        let active = shown.first { $0.name == selectedCategory }
        return GeometryReader { geometry in
        let diameter = min(geometry.size.width - 32, 300)
        let outerRadius = max(1, diameter / 2)
        let innerRatio: CGFloat = 0.5
        let innerRadius = outerRadius * innerRatio
        return VStack(spacing: 12) {
            Text(ar ? "ميزانية الفئات" : "Category budgets")
                .font(GhafTypography.heading(20, languageCode: lang)).foregroundStyle(theme.primaryText)
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                    let step = 360.0 / Double(max(shown.count, 1))
                    let gap = 6 / outerRadius * 180 / .pi
                    let start = -90 + Double(index) * step + gap / 2
                    let end = -90 + Double(index + 1) * step - gap / 2
                    let budgetShare = largestBudget > 0 ? NSDecimalNumber(decimal: item.budget / largestBudget).doubleValue : 0
                    let petalOuter = innerRatio + (1 - innerRatio) * budgetShare
                    let fraction = item.budget > 0 ? min(1, NSDecimalNumber(decimal: item.spent / item.budget).doubleValue) : 0
                    let visibleFraction = item.spent > 0 ? max(fraction, min(1, 6 / max((petalOuter - innerRatio) * outerRadius, 1))) : 0
                    let fillRadius = innerRatio + (petalOuter - innerRatio) * visibleFraction
                    GhafPetalSegment(start: start, end: end, inner: innerRatio, outer: petalOuter)
                        .fill(theme.primaryText.opacity(theme.isDark ? 0.16 : 0.10))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay {
                            if item.spent > 0 {
                                GhafPetalSegment(start: start, end: end, inner: innerRatio, outer: fillRadius).fill(theme.accent)
                            }
                        }
                        .overlay {
                            GhafPetalSegment(start: start, end: end, inner: innerRatio, outer: petalOuter).stroke(item.spent > item.budget ? theme.over : .clear, lineWidth: 2)
                        }
                        .opacity(selectedCategory == nil || selectedCategory == item.name ? 1 : 0.45)
                        .contentShape(GhafPetalSegment(start: start, end: end, inner: innerRatio, outer: petalOuter))
                }
                VStack(spacing: 3) {
                    if let active {
                        Text(active.name).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).lineLimit(1)
                        GhafMoneyLabel(amount: active.spent, currency: currency, languageCode: lang, size: 22, weight: .semibold)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        HStack(spacing: 3) {
                            Text("of").font(GhafTypography.body(13, languageCode: lang))
                            GhafMoneyLabel(amount: active.budget, currency: currency, languageCode: lang, size: 13)
                            Text("· \(percent(active.spent, of: active.budget))%").font(GhafTypography.body(13, languageCode: lang))
                        }.foregroundStyle(theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text(ar ? (hasSalary ? "دورة الراتب" : "هذا الشهر") : (hasSalary ? "This salary cycle" : "This month")).font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        GhafMoneyLabel(amount: totalSpent, currency: currency, languageCode: lang, size: 22, weight: .semibold)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        HStack(spacing: 3) {
                            Text("of").font(GhafTypography.body(13, languageCode: lang))
                            GhafMoneyLabel(amount: totalBudget, currency: currency, languageCode: lang, size: 13)
                        }.foregroundStyle(theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                    }
            }.frame(width: max(0, innerRadius * 2 - 20)).multilineTextAlignment(.center).foregroundStyle(theme.primaryText).allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let point = CGPoint(x: value.location.x - geometry.size.width / 2, y: value.location.y - outerRadius)
                let radius = hypot(point.x, point.y) / outerRadius
                guard radius >= innerRatio, radius <= 1, !shown.isEmpty else { withAnimation(.spring()) { selectedCategory = nil }; return }
                let degrees = (atan2(point.y, point.x) * 180 / .pi + 450).truncatingRemainder(dividingBy: 360)
                let index = min(shown.count - 1, Int(degrees / 360 * Double(shown.count)))
                withAnimation(reduceMotion ? nil : .spring()) { selectedCategory = selectedCategory == shown[index].name ? nil : shown[index].name }
            })
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ar ? "ميزانية الشهر" : "Monthly category budgets")
            .accessibilityValue("\(GhafFormat.shownMoney(totalSpent, currency: currency, languageCode: lang)) of \(GhafFormat.shownMoney(totalBudget, currency: currency, languageCode: lang)). Petals clockwise from 12 o'clock: \(shown.map(\.name).joined(separator: ", "))")
            Text(ar ? "اضغط على فئة لعرض مصروفاتها" : "Tap a category to see its spending")
                .font(GhafTypography.body(13, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(rows, id: \.name) { item in
                    let category = shown.first(where: { $0.name == item.name })?.name
                        ?? ((grouped && !all.prefix(6).contains(where: { $0.name == item.name })) ? (ar ? "أخرى" : "Other") : nil)
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring()) { selectedCategory = selectedCategory == category ? nil : category }
                        } label: {
                            HStack(spacing: 12) {
                            GhafCategoryIcon(category: item.name, tint: theme.accent, theme: theme)
                                .frame(width: 36, height: 36)
                                .background(theme.accent.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.name).font(GhafTypography.body(16, languageCode: lang, weight: .semibold)).lineLimit(2)
                                }
                                HStack(spacing: 3) { spentOf(item) }
                                    .font(GhafTypography.body(13, languageCode: lang))
                                    .foregroundStyle(item.spent > item.budget ? theme.over : theme.secondaryText)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 2)
                            }
                            .frame(height: 64)
                            .contentShape(Rectangle())
                            .foregroundStyle(theme.primaryText)
                            .opacity(selectedCategory == nil || selectedCategory == category ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        Button {
                        editingCategory = item.name
                        budgetEntry = NSDecimalNumber(decimal: item.budget).stringValue
                        } label: {
                            Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText).frame(width: 32, height: 44)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        }
        .frame(height: CGFloat(rows.count * 64) + 350)
        .padding(GhafMetrics.cardPadding).ghafStatsCard(theme: theme, radius: 22)
    }

    private func hasRecentSpending(_ category: String) -> Bool {
        let start = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: .now)!.start)!
        return expenses(in: DateInterval(start: start, end: .now)).contains { $0.category == category }
    }

    @ViewBuilder private func spentOf(_ item: (name: String, spent: Decimal, budget: Decimal)) -> some View {
        GhafMoneyLabel(amount: item.spent, currency: currency, languageCode: lang, size: 13, weight: .semibold)
        Text(ar ? "من" : "of")
        GhafMoneyLabel(amount: item.budget, currency: currency, languageCode: lang, size: 13, weight: .semibold)
    }

    private func percent(_ amount: Decimal, of budget: Decimal) -> Int {
        guard budget > 0 else { return 0 }
        return Int(NSDecimalNumber(decimal: amount * 100 / budget).doubleValue)
    }

    private var presetSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ar ? "اختر التوزيع" : "Choose a budget split").font(GhafTypography.heading(22, languageCode: lang)).foregroundStyle(theme.primaryText).frame(maxWidth: .infinity)
            ForEach(BudgetAllocation.Preset.allCases, id: \.self) { item in
                Button { settings.allocationPresetRaw = item.rawValue; showPresetSheet = false } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ar ? presetNameArabic(item) : item.name).font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                            Text(ar ? presetArabic(item) : item.description).font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 6) {
                            Text(item.title).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).monospacedDigit()
                            if preset == item { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                        }
                        .foregroundStyle(theme.primaryText)
                    }
                    .foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
            Text(ar ? "تستند قاعدة ٥٠/٣٠/٢٠ إلى كتاب Elizabeth Warren بعنوان All Your Worth (2005). أما التوزيعات الأخرى فتكيّفها لتناسب ارتفاع التكاليف الثابتة." : "The 50/30/20 rule comes from Elizabeth Warren's book All Your Worth (2005). The other splits adapt it for higher fixed costs.")
                .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }.padding(22).ghafBackground(theme: theme)
    }

    private func presetNameArabic(_ preset: BudgetAllocation.Preset) -> String {
        switch preset {
        case .balanced: "البطل"
        case .highRentCity: "المخطط"
        case .essentialsFirst: "المستكشف"
        case .guardian: "الحارس"
        }
    }

    private func presetArabic(_ preset: BudgetAllocation.Preset) -> String {
        switch preset {
        case .balanced: "للمصاريف الثابتة التي تقل عن نصف دخلك"
        case .highRentCity: "عندما يستحوذ الإيجار والفواتير على ٥٥٪ أو أكثر"
        case .essentialsFirst: "عندما ترتفع الفواتير ويبدأ الادخار بمبلغ أقل"
        case .guardian: "عندما تحتاج الأساسيات إلى الحصة الأكبر من دخلك"
        }
    }

    private func budgetEditor(_ name: String) -> some View {
        VStack(spacing: 18) {
            Text(ar ? "ميزانية \(name)" : "Edit \(name) budget").font(GhafTypography.heading(22, languageCode: lang)).foregroundStyle(theme.primaryText)
            Text(currency).font(GhafTypography.body(13, languageCode: lang, weight: .semibold)).foregroundStyle(theme.secondaryText)
            TextField("0", text: $budgetEntry).keyboardType(.decimalPad).multilineTextAlignment(.center).font(GhafTypography.number(30, weight: .semibold)).foregroundStyle(theme.primaryText)
            GhafPrimaryButton(title: ar ? "حفظ الميزانية" : "Save budget", theme: theme, languageCode: lang) {
                if let amount = Decimal(string: budgetEntry), amount >= 0 { var budgets = settings.categoryBudgets; budgets[name] = roundedBudget(amount); settings.categoryBudgets = budgets }
                editingCategory = nil
            }
        }.padding(24).ghafBackground(theme: theme)
    }

#if DEBUG
    private func runAutoSelection(scrollProxy: ScrollViewProxy) {
        let month = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: .now)!.start)!
        let actions: [(TimeInterval, () -> Void)] = [
            (2.0, { toggleBucket(.wants) }), (3.0, { toggleBucket(.savings) }),
            (4.0, { toggleBucket(.savings) }),
            (5.0, { toggleMonth(month) }), (6.0, { toggleMonth(month) })
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { scrollProxy.scrollTo("month-trend", anchor: .center) }
        for (delay, action) in actions { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) }
    }
#endif

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
            GhafMoneyLabel(amount: income, currency: incomeCurrency, languageCode: lang, size: 34)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
            Text(detail)
                .font(GhafTypography.body(13, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            if salaryCurrencyMismatch {
                Text(ar ? "يعرض الراتب بعملة \(incomeCurrency)؛ وتستخدم خطة الميزانية الدخل الشهري بعملة \(currency)."
                        : "Salary is shown in \(incomeCurrency); the budget plan uses monthly income in \(currency).")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: Auto-allocation

    private func allocationCard(needs: Decimal, wants: Decimal) -> some View {
        let names = ar ? ["الأساسيات", "الرغبات", "الادخار"] : ["Needs", "Wants", "Savings"]
        let colors = [theme.accent, theme.glow, theme.secondaryText]
        let planned = bucketSelected ? allocationIncome * preset.share(bucket) : allocationIncome
        let used: Decimal = bucket == .needs ? needs : bucket == .wants ? wants : allocationIncome - needs - wants
        return VStack(spacing: 14) {
            HStack {
                Text(ar ? presetNameArabic(preset) : preset.name)
                    .font(GhafTypography.body(20, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button { showPresetSheet = true } label: {
                    Image(systemName: ar ? "chevron.left" : "chevron.right")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }.buttonStyle(.plain)
            }
            if allocationIncome <= 0 {
                Text(ar ? "أضف دخلك الشهري من المزيد › الميزانية والفئات، أو راتبك من دورة الراتب، ليقسّمه غاف ٥٠/٣٠/٢٠."
                        : "Add your monthly income in More › Budget & categories, or your salary in Salary cycle, and Ghaf splits it using your selected budget plan.")
                    .font(GhafTypography.body(14, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 8) {
                    Text(ar ? "الدخل" : "Income")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    GhafMoneyLabel(amount: allocationIncome, currency: currency, languageCode: lang, size: 30, weight: .semibold)
                        .foregroundStyle(theme.primaryText)
                        .environment(\.layoutDirection, .leftToRight)
                    GeometryReader { proxy in
                        HStack(spacing: 3) {
                            ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                                Capsule().fill(colors[item.rawValue])
                                    .frame(width: max(4, (proxy.size.width - 6) * NSDecimalNumber(decimal: preset.share(item)).doubleValue))
                            }
                        }
                    }
                    .frame(height: 12)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { item in
                        Button { toggleBucket(item) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(colors[item.rawValue]).frame(width: 10, height: 10)
                                Text(names[item.rawValue]).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                GhafMoneyLabel(amount: allocationIncome * preset.share(item), currency: currency, languageCode: lang, size: 14, weight: .semibold)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text("\(Int(truncating: (preset.share(item) * 100) as NSNumber))%")
                                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText).frame(minWidth: 34, alignment: .trailing)
                            }
                            .foregroundStyle(theme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.horizontal, 12)
                            .background(bucketSelected && bucket == item ? theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06) : .clear,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(names[item.rawValue]), \(GhafFormat.shownMoney(allocationIncome * preset.share(item), currency: currency, languageCode: lang)), \(Int(truncating: (preset.share(item) * 100) as NSNumber))%")
                        .accessibilityAddTraits(bucketSelected && bucket == item ? .isSelected : [])
                    }
                }
                if bucketSelected {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Text(bucket == .savings ? (ar ? "المتبقي بعد الصرف" : "Left after spending") : (ar ? "المصروف" : "Spent"))
                            GhafMoneyLabel(amount: used, currency: currency, languageCode: lang, size: 13, weight: .semibold)
                            Text(ar ? "من" : "of")
                            GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 13, weight: .semibold)
                            if bucket == .savings { Text(ar ? "هدف الادخار" : "goal") }
                        }
                        .font(GhafTypography.body(13, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        if bucket == .savings {
                            Text(ar ? "ما يتبقى من دخلك بعد الأساسيات والرغبات." : "What remains from income after Needs and Wants.")
                                .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .ghafStatsCard(theme: theme, radius: 28)
    }

    // MARK: Pace

    /// Spending so far in needs and wants against the 80% plan, prorated to today.
    private func paceRow(needs: Decimal, wants: Decimal) -> some View {
        let elapsed = min(max(Date.now.timeIntervalSince(cycle.start) / cycle.duration, 0.03), 1)
        let expected = NSDecimalNumber(decimal: allocationIncome * 0.8).doubleValue * elapsed
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
        return VStack(alignment: .center, spacing: 10) {
            Text(ar ? "اتجاه الصرف" : "Spending trend")
                .font(GhafTypography.heading(20, languageCode: lang))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
            let average = months.map(\.total).reduce(0, +) / Double(months.count)
            Text("\(ar ? "متوسط" : "avg") · \(GhafCompactNumber.string(average, languageCode: lang))")
                .font(GhafTypography.body(11, languageCode: lang, weight: .semibold)).foregroundStyle(theme.secondaryText)
            if let selected = months.first(where: { $0.start == selectedMonth }),
               let index = months.firstIndex(where: { $0.start == selected.start }) {
                GeometryReader { proxy in
                    let width = min(190, proxy.size.width)
                    let center = proxy.size.width * (Double(index) + 0.5) / Double(months.count)
                    let x = min(max(center, width / 2), proxy.size.width - width / 2)
                    HStack(spacing: 5) {
                        Text(selected.start.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: lang))))
                        Text("·")
                        Text(GhafFormat.shownMoney(Decimal(selected.total), currency: currency, languageCode: lang)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: width, height: 28)
                    .background(theme.primaryText.opacity(theme.isDark ? 0.12 : 0.06), in: Capsule())
                    .position(x: x, y: 14)
                }
                .frame(height: 28)
                .accessibilityElement(children: .combine)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(months, id: \.start) { month in
                    let current = month.start == thisMonth.start
                    Button { toggleMonth(month.start) } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedMonth == nil ? (current ? theme.accent : theme.primaryText.opacity(0.22)) : theme.primaryText)
                                .frame(height: max(6, 70 * month.total / most))
                            Text(month.start.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: lang))))
                                .font(GhafTypography.body(11, languageCode: lang, weight: .semibold)).foregroundStyle(current ? theme.primaryText : theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottom).contentShape(Rectangle())
                        .opacity(selectedMonth == nil || selectedMonth == month.start ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(month.start.formatted(.dateTime.month(.wide).locale(Locale(identifier: lang))) + " " + GhafFormat.shownMoney(Decimal(month.total), currency: currency, languageCode: lang))
                    .accessibilityAddTraits(selectedMonth == month.start ? .isSelected : [])
                }
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    let y = 70 * average / most
                    Path { path in path.move(to: CGPoint(x: 0, y: 90 - y)); path.addLine(to: CGPoint(x: proxy.size.width, y: 90 - y)) }
                        .stroke(theme.secondaryText.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .allowsHitTesting(false)
            }
        }
            .padding(GhafMetrics.cardPadding)
        .ghafStatsCard(theme: theme, radius: 22)
    }
}
