import SwiftUI
import SwiftData
import Charts
import GhafCore

private struct BudgetPetal: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2
        func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle * .pi / 180) * radius * r,
                    y: center.y + sin(angle * .pi / 180) * radius * r)
        }
        let outerRadius = radius * outer, innerRadius = radius * inner
        let petalWidth = outerRadius * CGFloat((end - start) * .pi / 180)
        // Never more than half the radial depth, or the two side fillets cross and draw a spike.
        let corner = min(18, petalWidth * 0.25, (outerRadius - innerRadius) / 2)
        let outerInset = min((end - start) * 0.22, Double(atan(corner / max(outerRadius - corner, 1))) * 180 / .pi)
        let innerInset = min((end - start) * 0.22, Double(atan(corner / max(innerRadius + corner, 1))) * 180 / .pi)
        func arcControl(_ from: Double, _ to: Double, _ r: CGFloat) -> CGPoint {
            let middle = (from + to) / 2
            return point(middle, r / CGFloat(cos((to - from) * .pi / 360)))
        }
        var path = Path()
        path.move(to: point(start, outer - corner / radius))
        path.addQuadCurve(to: point(start + outerInset, outer), control: point(start, outer))
        path.addQuadCurve(to: point(end - outerInset, outer), control: arcControl(start + outerInset, end - outerInset, outer))
        path.addQuadCurve(to: point(end, outer - corner / radius), control: point(end, outer))
        path.addLine(to: point(end, inner + corner / radius))
        path.addQuadCurve(to: point(end - innerInset, inner), control: point(end, inner))
        path.addQuadCurve(to: point(start + innerInset, inner), control: arcControl(end - innerInset, start + innerInset, inner))
        path.addQuadCurve(to: point(start, inner + corner / radius), control: point(start, inner))
        path.addLine(to: point(start, outer - corner / radius))
        path.closeSubpath()
        return path
    }
}

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
        .sheet(isPresented: $showPresetSheet) { presetSheet.presentationDetents([.height(340)]).presentationCornerRadius(32) }
        .sheet(item: Binding(get: { editingCategory.map(EditCategory.init) }, set: { editingCategory = $0?.name })) { item in
            budgetEditor(item.name).presentationDetents([.height(320)]).presentationCornerRadius(32)
        }
        .onAppear {
#if DEBUG
            guard GhafScreenshotFixture.enabled else { return }
            if GhafScreenshotFixture.selection == "wants" { bucket = .wants; bucketSelected = true }
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
        let monthStart = calendar.dateInterval(of: .month, for: .now)!.start
        let totals = Dictionary(grouping: expenses(in: DateInterval(start: monthStart, end: calendar.dateInterval(of: .month, for: .now)!.end)), by: \.category)
            .mapValues { $0.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
        let historyStart = calendar.date(byAdding: .month, value: -3, to: monthStart)!
        let history = Dictionary(grouping: expenses(in: DateInterval(start: historyStart, end: monthStart)), by: \.category)
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
        let bucketAmount = income * preset.share(bucket)
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
        let all = rows.filter { $0.spent > 0 }
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
                    let petalOuter = innerRatio + (1 - innerRatio) * max(0.18, budgetShare)
                    let fraction = item.budget > 0 ? min(1, NSDecimalNumber(decimal: item.spent / item.budget).doubleValue) : 0
                    let fillRadius = innerRatio + (petalOuter - innerRatio) * fraction
                    BudgetPetal(start: start, end: end, inner: innerRatio, outer: petalOuter)
                        .fill(theme.primaryText.opacity(theme.isDark ? 0.07 : 0.05))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay {
                            // A fill thinner than 6pt draws as a spike once corners are rounded; show none instead.
                            if (fillRadius - innerRatio) * outerRadius >= 6 {
                                BudgetPetal(start: start, end: end, inner: innerRatio, outer: fillRadius).fill(theme.accent)
                            }
                        }
                        .overlay {
                            BudgetPetal(start: start, end: end, inner: innerRatio, outer: petalOuter).stroke(item.spent > item.budget ? theme.over : .clear, lineWidth: 2)
                        }
                        .opacity(selectedCategory == nil || selectedCategory == item.name ? 1 : 0.45)
                        .contentShape(BudgetPetal(start: start, end: end, inner: innerRatio, outer: petalOuter))
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
                        Text(ar ? "هذا الشهر" : "This month").font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
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
                                if item.spent > item.budget {
                                    Label(ar ? "تجاوز بمقدار \(GhafFormat.shownMoney(item.spent - item.budget, currency: currency, languageCode: lang))" : "Over by \(GhafFormat.shownMoney(item.spent - item.budget, currency: currency, languageCode: lang))", systemImage: "exclamationmark.circle")
                                        .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.over).lineLimit(1).minimumScaleFactor(0.65)
                                } else {
                                    // One line when it fits, otherwise two; never shrink the amounts below a readable size.

                                    ViewThatFits(in: .horizontal) {

                                        HStack(spacing: 3) { spentOf(item); Text("· \(percent(item.spent, of: item.budget))%") }

                                        VStack(alignment: .leading, spacing: 1) { HStack(spacing: 3) { spentOf(item) }; Text("\(percent(item.spent, of: item.budget))%") }

                                    }.font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 2)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(theme.primaryText.opacity(theme.isDark ? 0.12 : 0.08))
                                    Capsule().fill(item.spent > item.budget ? theme.over : theme.accent)
                                        .frame(width: proxy.size.width * min(1, item.budget > 0 ? NSDecimalNumber(decimal: item.spent / item.budget).doubleValue : 0))
                                }
                            }
                            .frame(width: 64, height: 6)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(ar ? "اختر التوزيع" : "Choose a budget split").font(GhafTypography.heading(22, languageCode: lang)).foregroundStyle(theme.primaryText).frame(maxWidth: .infinity)
            ForEach(BudgetAllocation.Preset.allCases, id: \.self) { item in
                Button { settings.allocationPresetRaw = item.rawValue; showPresetSheet = false } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(item.title).font(GhafTypography.body(16, languageCode: lang, weight: .semibold)); Spacer(); if preset == item { Image(systemName: "checkmark") } }
                        GeometryReader { geo in HStack(spacing: 2) { ForEach(BudgetAllocation.Bucket.allCases, id: \.self) { bucket in Rectangle().fill([theme.accent, theme.close, theme.comfortable][bucket.rawValue]).frame(width: geo.size.width * CGFloat(NSDecimalNumber(decimal: item.share(bucket)).doubleValue)) } } }.frame(height: 8).clipShape(Capsule())
                        Text(ar ? presetArabic(item) : item.description).font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    }.foregroundStyle(theme.primaryText).padding(12).background(theme.primaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }.padding(22).ghafBackground(theme: theme)
    }

    private func presetArabic(_ preset: BudgetAllocation.Preset) -> String {
        switch preset {
        case .balanced: "للمصاريف الثابتة التي تقل عن نصف دخلك"
        case .highRentCity: "حين يستهلك الإيجار والفواتير ٥٥٪ أو أكثر"
        case .essentialsFirst: "حين ترتفع الفواتير ويبدأ الادخار صغيراً"
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
            }.frame(height: 56)
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
            GhafMoneyLabel(amount: income, currency: currency, languageCode: lang, size: 34)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
            Text(detail)
                .font(GhafTypography.body(13, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: Auto-allocation

    private func allocationCard(needs: Decimal, wants: Decimal) -> some View {
        let names = ar ? ["الأساسيات", "الرغبات", "الادخار"] : ["Needs", "Wants", "Savings"]
        let colors = [theme.accent, theme.glow, theme.secondaryText]
        let planned = bucketSelected ? income * preset.share(bucket) : income
        let used: Decimal = bucketSelected ? (bucket == .needs ? needs : bucket == .wants ? wants : max(income - needs - wants, 0)) : needs + wants
        let ratio = planned > 0 ? min(max(NSDecimalNumber(decimal: used / planned).doubleValue, 0), 1.5) : 0
        let day = (calendar.dateComponents([.day], from: cycle.start, to: .now).day ?? 0) + 1
        let length = max(1, calendar.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? 30)
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(ar ? "التوزيع التلقائي" : "Auto-allocation")
                    .font(GhafTypography.body(20, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button { showPresetSheet = true } label: {
                    HStack(spacing: 4) { Text(preset.title); Image(systemName: "chevron.right") }
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }.buttonStyle(.plain)
            }
            if income <= 0 {
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
                    GhafMoneyLabel(amount: income, currency: currency, languageCode: lang, size: 30, weight: .semibold)
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
                                GhafMoneyLabel(amount: income * preset.share(item), currency: currency, languageCode: lang, size: 14, weight: .semibold)
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
                        .accessibilityLabel("\(names[item.rawValue]), \(GhafFormat.shownMoney(income * preset.share(item), currency: currency, languageCode: lang)), \(Int(truncating: (preset.share(item) * 100) as NSNumber))%")
                        .accessibilityAddTraits(bucketSelected && bucket == item ? .isSelected : [])
                    }
                }
                HStack(spacing: 5) {
                    Text(ar ? "المصروف" : "Spent").lineLimit(1)
                    GhafMoneyLabel(amount: used, currency: currency, languageCode: lang, size: 13).lineLimit(1).minimumScaleFactor(0.7)
                    Text(ar ? "من" : "of").lineLimit(1)
                    GhafMoneyLabel(amount: planned, currency: currency, languageCode: lang, size: 13).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(ratio.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: lang)))).lineLimit(1)
                }
                .font(GhafTypography.body(13, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.elevatedSurface)
                        Capsule().fill(ratio > 1 ? theme.over : (bucketSelected ? colors[bucket.rawValue] : theme.accent))
                            .frame(width: max(6, proxy.size.width * min(ratio, 1)))
                    }
                }
                .frame(height: 6)
                HStack(spacing: 4) {
                    GhafMoneyLabel(amount: max(planned - used, 0), currency: currency, languageCode: lang, size: 13)
                    Text(ar ? "متبقٍ · اليوم" : "left · Day")
                    Text("\(day)")
                    Text(ar ? "من" : "of")
                    Text("\(length)")
                }
                .font(GhafTypography.body(13, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.75)
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
        return VStack(alignment: .center, spacing: 10) {
            Text(ar ? "اتجاه الصرف" : "Spending trend")
                .font(GhafTypography.heading(20, languageCode: lang))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
            let average = months.map(\.total).reduce(0, +) / Double(months.count)
            Text("\(ar ? "متوسط" : "avg") · \(GhafCompactNumber.string(average, languageCode: lang))")
                .font(GhafTypography.body(11, languageCode: lang, weight: .semibold)).foregroundStyle(theme.secondaryText)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(months, id: \.start) { month in
                    let current = month.start == thisMonth.start
                    Button { toggleMonth(month.start) } label: {
                        VStack(spacing: 8) {
                            if selectedMonth == month.start {
                                Text("\(GhafCompactNumber.string(month.total, languageCode: lang)) · \(month.start.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: lang))))")
                                    .font(GhafTypography.number(11, weight: .bold)).foregroundStyle(theme.surface).padding(.horizontal, 6).padding(.vertical, 3).background(theme.primaryText, in: Capsule()).lineLimit(1).minimumScaleFactor(0.65)
                            }
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
