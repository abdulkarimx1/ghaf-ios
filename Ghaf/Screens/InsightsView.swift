import SwiftUI
import SwiftData
import Charts

private struct GhafCategoryTotal: Identifiable {
    let category: String
    let amount: Double
    var id: String { category }
}

struct GhafInsightsView: View {
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
        monthTransactions.filter { $0.direction == "debit" }
    }

    private var incomeTransactions: [GhafTransaction] {
        monthTransactions.filter { $0.direction == "credit" }
    }

    private var totalExpenses: Decimal {
        expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var totalIncome: Decimal {
        incomeTransactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var categoryTotals: [GhafCategoryTotal] {
        let groups = Dictionary(grouping: expenses, by: \.category)
        return groups.map { category, items in
            let total = items.reduce(Decimal.zero) { $0 + $1.amount }
            return GhafCategoryTotal(
                category: category,
                amount: NSDecimalNumber(decimal: total).doubleValue
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var net: Decimal { totalIncome - totalExpenses }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    headlineCard
                    summaryGrid
                    categoryChart
                    categoryList
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(settings.languageCode == "ar" ? "ملخص الشهر" : "MONTHLY OVERVIEW")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(theme.secondaryText)
            Text(settings.languageCode == "ar" ? "نظرة عامة" : "Insights")
                .font(GhafTypography.display(32, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(Date.now.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: settings.languageCode))))
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.languageCode == "ar" ? "صافي هذا الشهر" : "NET THIS MONTH")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(theme.accentContrast.opacity(0.72))

            Text(GhafFormat.money(net, currency: settings.currency, languageCode: settings.languageCode))
                .font(GhafTypography.number(34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.accentContrast)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(settings.languageCode == "ar" ? "الدخل المسجل بعد خصم المصروفات." : "Recorded income after expenses.")
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.accentContrast.opacity(0.78))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
    }

    private var summaryGrid: some View {
        HStack(spacing: 10) {
            summaryCard(
                title: settings.languageCode == "ar" ? "المصروفات" : "EXPENSES",
                amount: totalExpenses,
                color: theme.debit,
                symbol: "arrow.up.right"
            )
            summaryCard(
                title: settings.languageCode == "ar" ? "الدخل" : "INCOME",
                amount: totalIncome,
                color: theme.credit,
                symbol: "arrow.down.left"
            )
        }
    }

    private func summaryCard(title: String, amount: Decimal, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(GhafTypography.body(9, languageCode: settings.languageCode, weight: .bold))
                    .tracking(1)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.secondaryText)

            Text(GhafFormat.money(amount, currency: settings.currency, languageCode: settings.languageCode))
                .font(GhafTypography.number(18, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.outline.opacity(0.7), lineWidth: 1))
    }

    private var categoryChart: some View {
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
                    .cornerRadius(5)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.custom("IBMPlexSans-Regular", size: 10))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(height: CGFloat(min(categoryTotals.count, 6)) * 37 + 12)
            }
        }
        .padding(18)
        .ghafCard(theme: theme, radius: 20)
    }

    private var categoryList: some View {
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
                                .font(GhafTypography.body(13, languageCode: settings.languageCode, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(theme.outline.opacity(0.6))
                                    Capsule()
                                        .fill(theme.accent.opacity(0.78))
                                        .frame(width: geometry.size.width * relativeAmount(item.amount))
                                }
                            }
                            .frame(height: 4)
                        }
                        Spacer(minLength: 4)
                        Text(GhafFormat.money(Decimal(item.amount), currency: settings.currency, languageCode: settings.languageCode))
                            .font(GhafTypography.number(12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                    }
                    if index < categoryTotals.count - 1 {
                        Divider().overlay(theme.outline.opacity(0.8))
                    }
                }
            }
        }
        .padding(18)
        .ghafCard(theme: theme, radius: 20)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(subtitle)
                .font(GhafTypography.body(11, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func relativeAmount(_ amount: Double) -> CGFloat {
        let maxAmount = categoryTotals.first?.amount ?? 1
        guard maxAmount > 0 else { return 0 }
        return CGFloat(min(max(amount / maxAmount, 0), 1))
    }
}
