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
    @State private var categoryTransactions: String?
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
    private var plan: GhafBudgetPlan { GhafBudgetPlan(settings: settings, transactions: transactions, calendar: calendar, now: GhafClock.now) }
    private var hasSalary: Bool { plan.hasSalary }
    private var preset: BudgetAllocation.Preset { plan.preset }
    private var income: Decimal { plan.income }
    private var incomeCurrency: String { plan.incomeCurrency }
    private var salaryCurrencyMismatch: Bool { plan.salaryCurrencyMismatch }
    private var allocationIncome: Decimal { plan.allocationIncome }
    private var cycle: DateInterval { plan.cycle }
    private func expenses(in range: DateInterval) -> [GhafTransaction] { plan.expenses(in: range) }

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
        .sheet(isPresented: $showPresetSheet) { presetSheet.ghafBottomCard(theme: theme, languageCode: lang) }
        .sheet(item: Binding(get: { editingCategory.map(EditCategory.init) }, set: { editingCategory = $0?.name })) { item in
            budgetEditor(item.name).ghafBottomCard(theme: theme, languageCode: lang)
        }
        .sheet(item: Binding(get: { categoryTransactions.map(EditCategory.init) }, set: { categoryTransactions = $0?.name })) { item in
            GhafTransactionListSheet(title: GhafLocalization.category(item.name, languageCode: lang),
                                     transactions: expenses(in: cycle).filter { $0.category == item.name },
                                     theme: theme, languageCode: lang)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .ghafSheetFrame(theme: theme)
                .ghafDirection(lang)
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
            if GhafScreenshotFixture.selection == "petal" { selectedCategory = monthlySpendByCategory.first?.name }
            if GhafScreenshotFixture.selection == "preset-card" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showPresetSheet = true } }
            if GhafScreenshotFixture.selection == "over" {
                var budgets = settings.categoryBudgets; budgets["Subscriptions"] = 1; settings.categoryBudgets = budgets
            }
            if GhafScreenshotFixture.selection == "preset" { showPresetSheet = true }
            if GhafScreenshotFixture.selection == "edit-budget", let category = monthlySpendByCategory.first?.name {
                editingCategory = category; budgetEntry = NSDecimalNumber(decimal: monthlySpendByCategory.first?.budget ?? 0).stringValue
            }
            if GhafScreenshotFixture.selection == "month" {
                selectedMonth = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: GhafClock.now)!.start)
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

    private var monthlySpendByCategory: [(name: String, spent: Decimal, budget: Decimal)] { plan.categoryRows }

    private var petalBudgetCard: some View {
        let rows = monthlySpendByCategory.filter { $0.spent > 0 }
        let all = rows.filter { $0.budget > 0 }
        let grouped = all.count > 8
        let shown = Array(all.prefix(grouped ? 7 : 8)) + (grouped ? [(name: ar ? "أخرى" : "Other", spent: all.dropFirst(7).reduce(Decimal.zero) { $0 + $1.spent }, budget: all.dropFirst(7).reduce(Decimal.zero) { $0 + $1.budget })] : [])
        let totalSpent = shown.reduce(Decimal.zero) { $0 + $1.spent }
        let totalBudget = shown.reduce(Decimal.zero) { $0 + $1.budget }
        return GeometryReader { geometry in
        let diameter = min(geometry.size.width - 32, 300)
        let outerRadius = max(1, diameter / 2)
        let innerRatio: CGFloat = 0.16
        return VStack(spacing: 8) {
            Text(ar ? "ميزانية الفئات" : "Category budgets")
                .font(GhafTypography.heading(20, languageCode: lang)).foregroundStyle(theme.primaryText)
            VStack(spacing: 3) {
                Text(ar ? (hasSalary ? "دورة الراتب · المصروف من الميزانية" : "هذا الشهر · المصروف من الميزانية") : (hasSalary ? "This salary cycle · spent of budget" : "This month · spent of budget"))
                    .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    GhafMoneyLabel(amount: totalSpent, currency: currency, languageCode: lang, size: 18, weight: .semibold)
                    Text(ar ? "من" : "of").font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    GhafMoneyLabel(amount: totalBudget, currency: currency, languageCode: lang, size: 18, weight: .semibold)
                }.foregroundStyle(theme.primaryText).lineLimit(1).minimumScaleFactor(0.75)
            }
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                    let step = 360.0 / Double(max(shown.count, 1))
                    let gap = 3 / outerRadius * 180 / .pi
                    let start = -90 + Double(index) * step + gap / 2
                    let end = -90 + Double(index + 1) * step - gap / 2
                    let radii = BudgetAllocation.petalRadii(budget: item.budget, spent: item.spent, innerRadius: Double(innerRatio))
                    let fillRadius = CGFloat(radii.fill)
                    let petalColor = item.spent > item.budget ? theme.over : theme.accent
                    GhafPetalSegment(start: start, end: end, inner: innerRatio, outer: 1)
                        .fill(petalColor.opacity(theme.isDark ? 0.25 : 0.18))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay {
                            // Anything spent must be visible (V10: AED 25 of 1,195 looked empty): floor the fill at 8% of the band.
                            if item.spent > 0 {
                                GhafPetalSegment(start: start, end: end, inner: innerRatio,
                                                 outer: max(fillRadius, innerRatio + (1 - innerRatio) * 0.08))
                                    .fill(petalColor)
                                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: fillRadius)
                            }
                        }
                        .overlay {
                            GeometryReader { labelGeometry in
                                let angle = (start + end) / 2
                                let radians = angle * .pi / 180
                                // Label sits in the larger band: the dark budget area (light text) or, once spending
                                // passes half the radius, inside the light spent fill (dark text) once it is wide enough there. Never across both.
                                let onFill = fillRadius >= 0.72 && item.spent > 0
                                let radial = outerRadius * (onFill ? (innerRatio + fillRadius) / 2 + 0.04 : (max(fillRadius, innerRatio) + 1) / 2)
                                let amount = GhafFormat.balancesHidden
                                    ? GhafFormat.hiddenMoney(item.spent, currency: currency, languageCode: lang)
                                    : (GhafMoneyLabel.formatter(languageCode: lang, currency: currency).string(from: item.spent as NSDecimalNumber) ?? "0")
                                VStack(spacing: 0) {
                                    Text(amount).font(GhafTypography.body(15, languageCode: lang, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(GhafLocalization.category(item.name, languageCode: lang)).font(GhafTypography.body(12, languageCode: lang)).lineLimit(1).minimumScaleFactor(0.7)
                                    if item.spent > item.budget { Text(ar ? "تجاوز" : "Over").font(GhafTypography.body(10, languageCode: lang, weight: .semibold)).lineLimit(1) }
                                }
                                .foregroundStyle(onFill ? theme.background : theme.primaryText)
                                .multilineTextAlignment(.center)
                                .frame(width: max(52, min(outerRadius * 0.66, 2 * radial * CGFloat(sin(step / 2 * .pi / 180)) - 8)), height: 42)
                                .position(x: labelGeometry.size.width / 2 + CGFloat(cos(radians)) * radial,
                                          y: labelGeometry.size.height / 2 + CGFloat(sin(radians)) * radial)
                                .accessibilityHidden(true)
                            }
                        }
                        .opacity(selectedCategory == nil || selectedCategory == item.name ? 1 : 0.45)
                        .contentShape(GhafPetalSegment(start: start, end: end, inner: innerRatio, outer: 1))
                }
                if shown.isEmpty {
                    Text(ar ? "لا يوجد إنفاق في هذه الدورة." : "No spending in this cycle.")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(width: diameter * 0.72, height: diameter * 0.72)
                        .ghafEntrance(1)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let point = CGPoint(x: value.location.x - geometry.size.width / 2, y: value.location.y - outerRadius)
                let radius = hypot(point.x, point.y) / outerRadius
                guard radius >= innerRatio, radius <= 1, !shown.isEmpty else { withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)) { selectedCategory = nil }; return }
                let degrees = (atan2(point.y, point.x) * 180 / .pi + 450).truncatingRemainder(dividingBy: 360)
                guard let index = CategoryTaxonomy.petalIndex(angleDegrees: degrees, count: shown.count, isRightToLeft: ar) else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)) { selectedCategory = selectedCategory == shown[index].name ? nil : shown[index].name }
            })
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ar ? "ميزانية الشهر" : "Monthly category budgets")
            .accessibilityValue(ar
                ? "\(GhafFormat.shownMoney(totalSpent, currency: currency, languageCode: lang)) من \(GhafFormat.shownMoney(totalBudget, currency: currency, languageCode: lang)). ترتيب الفئات باتجاه عقارب الساعة بدءًا من الساعة 12: \(shown.map { GhafLocalization.category($0.name, languageCode: lang) }.joined(separator: "، ")). الفئة المحددة: \(selectedCategory.map { GhafLocalization.category($0, languageCode: lang) } ?? "لا شيء")."
                : "\(GhafFormat.shownMoney(totalSpent, currency: currency, languageCode: lang)) of \(GhafFormat.shownMoney(totalBudget, currency: currency, languageCode: lang)). Petals clockwise from 12 o'clock: \(shown.map { GhafLocalization.category($0.name, languageCode: lang) }.joined(separator: ", ")). Selected: \(selectedCategory.map { GhafLocalization.category($0, languageCode: lang) } ?? "none")")
            Text(ar ? "اضغط على فئة لعرض مصروفاتها" : "Tap a category to see its spending")
                .font(GhafTypography.body(13, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(rows, id: \.name) { item in
                    let category = shown.first(where: { $0.name == item.name })?.name
                        ?? ((grouped && !all.prefix(7).contains(where: { $0.name == item.name })) ? (ar ? "أخرى" : "Other") : nil)
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
                                    Text(GhafLocalization.category(item.name, languageCode: lang)).font(GhafTypography.body(16, languageCode: lang, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    if item.spent > item.budget {
                                        Text(ar ? "تجاوز الميزانية" : "Over budget")
                                            .font(GhafTypography.body(10, languageCode: lang, weight: .semibold))
                                            .foregroundStyle(theme.over)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(theme.over.opacity(0.12), in: Capsule())
                                    }
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
                        if selectedCategory == category {
                            Button(ar ? "عرض الكل" : "View all") { categoryTransactions = item.name }
                                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(minHeight: 44)
                                .accessibilityHint(ar ? "عرض عمليات هذه الفئة في دورة الميزانية الحالية" : "Show this category's transactions in the current budget period")
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        }
        .frame(height: CGFloat(rows.count * 64) + 430)
        .padding(GhafMetrics.cardPadding)
        .frame(maxWidth: .infinity)
        .ghafStatsCard(theme: theme, radius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func hasRecentSpending(_ category: String) -> Bool {
        let start = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: GhafClock.now)!.start)!
        return expenses(in: DateInterval(start: start, end: GhafClock.now)).contains { $0.category == category }
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
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text(ar ? presetNameArabic(item) : item.name)
                                .font(GhafTypography.body(17, languageCode: lang, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.title)
                                .font(GhafTypography.number(15, weight: .semibold))
                                .foregroundStyle(preset == item ? theme.accent : theme.secondaryText)
                                .environment(\.layoutDirection, .leftToRight)
                            if preset == item {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        Text(ar ? presetArabic(item) : item.description)
                            .font(GhafTypography.body(13, languageCode: lang))
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GeometryReader { proxy in
                            HStack(spacing: 3) {
                                ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { bucket in
                                    Capsule().fill([theme.accent, theme.glow, theme.secondaryText][bucket.rawValue])
                                        .frame(width: max(4, (proxy.size.width - 6) * NSDecimalNumber(decimal: item.share(bucket)).doubleValue))
                                }
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .background(preset == item ? theme.accent.opacity(0.12) : theme.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ar ? presetNameArabic(item) : item.name), \(item.title)")
                .accessibilityHint(ar ? presetArabic(item) : item.description)
                .accessibilityAddTraits(preset == item ? .isSelected : [])
            }
            Text(ar ? "الأساسيات / الرغبات / الادخار" : "Needs / wants / savings")
                .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity).padding(.top, 2)
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
        case .highRentCity: "عندما يستحوذ الإيجار والفواتير على 55٪ أو أكثر"
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
                if let amount = Decimal(string: budgetEntry), amount >= 0 { var budgets = settings.categoryBudgets; budgets[name] = plan.roundedBudget(amount); settings.categoryBudgets = budgets }
                editingCategory = nil
            }
        }.padding(24).ghafBackground(theme: theme)
    }

#if DEBUG
    private func runAutoSelection(scrollProxy: ScrollViewProxy) {
        let month = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: GhafClock.now)!.start)!
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
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: GhafClock.now), to: cycle.end).day ?? 0)
        let started = cycle.start.formatted(.dateTime.day().month(.abbreviated).locale(GhafLocale.locale(identifier: lang)))
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
        let used: Decimal = bucket == .needs ? needs : bucket == .wants ? wants
            : BudgetAllocation.remainingAfterSpending(income: allocationIncome, needs: needs, wants: wants)
        return VStack(spacing: 14) {
            Button { showPresetSheet = true } label: {
                HStack {
                    Text(ar ? presetNameArabic(preset) : preset.name)
                        .font(GhafTypography.body(20, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Image(systemName: ar ? "chevron.left" : "chevron.right")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if allocationIncome <= 0 {
                Text(ar ? "أضف دخلك الشهري من المزيد › الميزانية والفئات، أو راتبك من دورة الراتب، ليقسّمه غاف 50/30/20."
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
                        if bucket == .savings {
                            HStack(spacing: 5) {
                                Text(ar ? "المتبقي" : "Remaining")
                                GhafMoneyLabel(amount: used, currency: currency, languageCode: lang, size: 13, weight: .semibold)
                                Text("·")
                                Text(ar ? "هدف الادخار" : "savings goal")
                                GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 13, weight: .semibold)
                                if BudgetAllocation.savingsGoalReached(remaining: used, goal: planned) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.credit)
                                }
                            }
                            .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                            .lineLimit(1).minimumScaleFactor(0.65)
                            Text(ar ? "المبلغ المتبقي من الدخل بعد مصروفات الأساسيات والرغبات المسجلة."
                                    : "Income remaining after recorded Needs and Wants spending.")
                                .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        } else {
                            HStack(spacing: 5) {
                                Text(ar ? "المصروف" : "Spent")
                                GhafMoneyLabel(amount: used, currency: currency, languageCode: lang, size: 13, weight: .semibold)
                                Text(ar ? "من" : "of")
                                GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 13, weight: .semibold)
                            }
                            .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                            .lineLimit(1).minimumScaleFactor(0.7)
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
        let elapsed = min(max(GhafClock.now.timeIntervalSince(cycle.start) / cycle.duration, 0.03), 1)
        let expected = NSDecimalNumber(decimal: allocationIncome * 0.8).doubleValue * elapsed
        let actual = NSDecimalNumber(decimal: needs + wants).doubleValue
        let pace = expected > 0 ? (actual - expected) / expected : 0
        let percent = Int((abs(pace) * 100).rounded())
        let day = (calendar.dateComponents([.day], from: cycle.start, to: GhafClock.now).day ?? 0) + 1
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.ghafPress)
        .accessibilityHint(ar ? "يفتح إعدادات دورة الراتب" : "Opens salary cycle settings")
    }

    // MARK: Six-month trend

    private var trendCard: some View {
        let thisMonth = calendar.dateInterval(of: .month, for: GhafClock.now)!
        let months: [(start: Date, total: Double)] = (0..<6).reversed().map { back in
            let start = calendar.date(byAdding: .month, value: -back, to: thisMonth.start)!
            let range = calendar.dateInterval(of: .month, for: start)!
            let sum = expenses(in: range).reduce(Decimal.zero) { $0 + $1.spendingAmount }
            return (start, NSDecimalNumber(decimal: sum).doubleValue)
        }
        let most = max(months.map(\.total).max() ?? 0, 1)
        return VStack(alignment: .center, spacing: 10) {
            Text(ar ? "اتجاه المصروف" : "Spending trend")
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
                        GhafMoneyLabel(amount: Decimal(selected.total), currency: currency, languageCode: lang,
                                       size: 12, weight: .semibold)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: width, height: 28)
                    .background(theme.primaryText.opacity(theme.isDark ? 0.12 : 0.06), in: Capsule())
                    .position(x: x, y: 14)
                }
                .frame(height: 28)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(selected.start.formatted(.dateTime.month(.wide).locale(GhafLocale.locale(identifier: lang)))
                                    + " · " + GhafFormat.shownMoney(Decimal(selected.total), currency: currency, languageCode: lang))
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(months, id: \.start) { month in
                    let current = month.start == thisMonth.start
                    Button { toggleMonth(month.start) } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedMonth == nil ? (current ? theme.accent : theme.primaryText.opacity(0.22)) : theme.primaryText)
                                .frame(height: max(6, 70 * month.total / most))
                            Text(month.start.formatted(.dateTime.month(.abbreviated).locale(GhafLocale.locale(identifier: lang))))
                                .font(GhafTypography.body(11, languageCode: lang, weight: .semibold)).foregroundStyle(current ? theme.primaryText : theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottom).contentShape(Rectangle())
                        .opacity(selectedMonth == nil || selectedMonth == month.start ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(month.start.formatted(.dateTime.month(.wide).locale(GhafLocale.locale(identifier: lang))) + " " + GhafFormat.shownMoney(Decimal(month.total), currency: currency, languageCode: lang))
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

private struct GhafPetalOuterEdge: Shape {
    let start: Double
    let end: Double
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let circleRadius = min(rect.width, rect.height) / 2 * radius
        var path = Path()
        path.addArc(center: center, radius: circleRadius,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}
