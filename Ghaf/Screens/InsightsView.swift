import SwiftUI
import SwiftData
import Charts

private struct GhafCategoryTotal: Identifiable {
    let category: String
    let amount: Double
    var id: String { category }
}

struct GhafInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var monthTransactions: [GhafTransaction] {
        transactions.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
                && $0.currency == settings.currency
        }
    }

    private var expenses: [GhafTransaction] {
        monthTransactions.filter(\.isExpense)
    }

    private var totalExpenses: Decimal {
        expenses.reduce(Decimal.zero) { $0 + $1.spendingAmount }
    }

    private var totalIncome: Decimal {
        monthTransactions.reduce(Decimal.zero) { $0 + $1.incomeAmount }
    }

    private var categoryTotals: [GhafCategoryTotal] {
        let groups = Dictionary(grouping: expenses, by: \.category)
        return groups.map { category, items in
            let total = items.reduce(Decimal.zero) { $0 + $1.spendingAmount }
            return GhafCategoryTotal(
                category: category,
                amount: NSDecimalNumber(decimal: total).doubleValue
            )
        }
        .filter { $0.amount > 0 }
        .sorted { $0.amount > $1.amount }
    }

    private var net: Decimal { totalIncome - totalExpenses }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Category totals are grouped once per render and shared by the chart and list.
                let totals = categoryTotals
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    GhafScreenTitle(title: settings.languageCode == "ar" ? "التحليلات" : "Insights",
                                    subtitle: Date.now.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: settings.languageCode))),
                                    languageCode: settings.languageCode, theme: theme, onClose: { dismiss() })
                    headlineCard.ghafEntrance(0)
                    forecastCard.ghafEntrance(1)
                    categoryChart(totals).ghafEntrance(2)
                    categoryList(totals).ghafEntrance(3)
                }
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
        }
        .ghafDirection(settings.languageCode)
    }

    /// Month-end projection from this month's pace and the usual month (statistics, not a promise).
    @ViewBuilder
    private var forecastCard: some View {
        let ar = settings.languageCode == "ar"
        if let forecast = GhafLedgerAnswers.monthForecast(transactions: transactions, currency: settings.currency),
           forecast.spentSoFar > 0 {
            let ratio = forecast.typicalMonth.map { NSDecimalNumber(decimal: forecast.projected / max($0, 1)).doubleValue }
            VStack(alignment: .leading, spacing: 10) {
                Label(ar ? "توقع نهاية الشهر" : "Month-end forecast", systemImage: "chart.line.uptrend.xyaxis")
                    .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                GhafMoneyLabel(amount: forecast.projected, currency: settings.currency, languageCode: settings.languageCode, size: 28)
                    .foregroundStyle(theme.primaryText)
                if let typical = forecast.typicalMonth, let ratio {
                    ProgressView(value: min(ratio, 1.5), total: 1.5)
                        .tint(ratio > 1.1 ? theme.over : theme.accent)
                    GhafMoneyText.text(ratio > 1.1
                         ? (ar ? "أعلى من شهرك المعتاد (\(GhafFormat.shownMoney(typical, currency: settings.currency, languageCode: settings.languageCode)))."
                               : "Above your usual month of \(GhafFormat.shownMoney(typical, currency: settings.currency, languageCode: settings.languageCode)).")
                         : (ar ? "ضمن شهرك المعتاد (\(GhafFormat.shownMoney(typical, currency: settings.currency, languageCode: settings.languageCode)))."
                               : "In line with your usual month of \(GhafFormat.shownMoney(typical, currency: settings.currency, languageCode: settings.languageCode))."), size: 13)
                        .font(GhafTypography.body(13, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
                Text(ar ? "تقدير من وتيرة هذا الشهر وآخر ٣ أشهر." : "Estimate from this month's pace and your last 3 months.")
                    .font(GhafTypography.body(11, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ghafCard(theme: theme)
        }
    }

    private var headlineCard: some View {
        VStack(spacing: 16) {
            Text(settings.languageCode == "ar" ? "صافي هذا الشهر" : "Net this month")
                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                .foregroundStyle(theme.inkText.opacity(0.7))
            GhafMoneyLabel(amount: net, currency: settings.currency, languageCode: settings.languageCode, size: 38)
                .foregroundStyle(theme.inkText)
            HStack(spacing: 10) {
                summaryCard(title: settings.languageCode == "ar" ? "المصروفات" : "Spent",
                            amount: totalExpenses, color: theme.inkDebit, symbol: "arrow.down.right")
                summaryCard(title: settings.languageCode == "ar" ? "الدخل" : "Income",
                            amount: totalIncome, color: theme.inkCredit, symbol: "arrow.up.right")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .ghafGlassHero(theme: theme, radius: 28, fallback: theme.ink)
    }

    private func summaryCard(title: String, amount: Decimal, color: Color, symbol: String) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .bold))
                .foregroundStyle(color)
            GhafMoneyLabel(amount: amount, currency: settings.currency, languageCode: settings.languageCode, size: 17)
                .foregroundStyle(theme.inkText)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(theme.inkText.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func categoryChart(_ categoryTotals: [GhafCategoryTotal]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(
                settings.languageCode == "ar" ? "الصرف حسب الفئة" : "Spending by category",
                subtitle: settings.languageCode == "ar" ? "أين ذهبت أموالك هذا الشهر" : "Where your money went this month"
            )

            if categoryTotals.isEmpty {
                Text(settings.languageCode == "ar" ? "لا توجد بيانات صرف لهذا الشهر." : "No spending data for this month.")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 25)
            } else {
                Chart(categoryTotals.prefix(6)) { item in
                    BarMark(
                        x: .value("Amount", item.amount),
                        y: .value("Category", GhafLocalization.category(item.category, languageCode: settings.languageCode))
                    )
                    .foregroundStyle(theme.accent.gradient)
                    .cornerRadius(8)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.custom("IBMPlexSans-Regular", size: 12))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(height: CGFloat(min(categoryTotals.count, 6)) * 37 + 12)
            }
        }
        .padding(20)
        .ghafCard(theme: theme)
    }

    private func categoryList(_ categoryTotals: [GhafCategoryTotal]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                settings.languageCode == "ar" ? "تفصيل الفئات" : "Category breakdown",
                subtitle: settings.languageCode == "ar" ? "مرتبة من الأعلى إنفاقاً" : "Ranked by highest spend"
            )

            if categoryTotals.isEmpty {
                Text(settings.languageCode == "ar" ? "سيظهر التفصيل بعد تسجيل المصروفات." : "Your breakdown will appear after expenses are recorded.")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(Array(categoryTotals.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 11) {
                        GhafCategoryIcon(category: item.category, tint: theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(GhafLocalization.category(item.category, languageCode: settings.languageCode))
                                .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(theme.elevatedSurface)
                                    Capsule()
                                        .fill(theme.accent.opacity(0.78))
                                        .frame(width: geometry.size.width * relativeAmount(item.amount, max: categoryTotals.first?.amount ?? 1))
                                }
                            }
                            .frame(height: 6)
                        }
                        Spacer(minLength: 4)
                        GhafMoneyLabel(amount: Decimal(item.amount), currency: settings.currency,
                                       languageCode: settings.languageCode, size: 14)
                            .foregroundStyle(theme.primaryText)
                    }
                    if index < categoryTotals.count - 1 {
                        Divider().overlay(theme.outline.opacity(0.8))
                    }
                }
            }
        }
        .padding(20)
        .ghafCard(theme: theme)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(subtitle)
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func relativeAmount(_ amount: Double, max maxAmount: Double) -> CGFloat {
        guard maxAmount > 0 else { return 0 }
        return CGFloat(min(max(amount / maxAmount, 0), 1))
    }
}
