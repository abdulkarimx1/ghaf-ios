import SwiftUI
import SwiftData
import Charts

private struct GhafCategoryTotal: Identifiable {

    let category: String
    let amount: Double

    var id: String {
        category
    }
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
            Calendar.current.isDate(
                $0.date,
                equalTo: Date(),
                toGranularity: .month
            ) && $0.currency == settings.currency
        }
    }

    private var expenses: [GhafTransaction] {

        monthTransactions.filter {
            $0.direction == "debit"
        }
    }

    private var incomeTransactions: [GhafTransaction] {

        monthTransactions.filter {
            $0.direction == "credit"
        }
    }

    private var totalExpenses: Decimal {

        expenses.reduce(Decimal.zero) {
            $0 + $1.amount
        }
    }

    private var totalIncome: Decimal {

        incomeTransactions.reduce(Decimal.zero) {
            $0 + $1.amount
        }
    }

    private var categoryTotals: [GhafCategoryTotal] {

        let groups = Dictionary(
            grouping: expenses,
            by: \.category
        )

        return groups.map { category, items in

            let total = items.reduce(Decimal.zero) {
                $0 + $1.amount
            }

            return GhafCategoryTotal(
                category: category,
                amount: NSDecimalNumber(
                    decimal: total
                ).doubleValue
            )

        }
        .sorted {
            $0.amount > $1.amount
        }
    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(alignment: .leading, spacing: 24) {

                    Text(Date.now.formatted(
                        .dateTime.month(.wide).year()
                    ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                    HStack(spacing: 12) {

                        summaryCard(
                            title: "EXPENSES",
                            amount: totalExpenses,
                            color: theme.debit
                        )

                        summaryCard(
                            title: "INCOME",
                            amount: totalIncome,
                            color: theme.credit
                        )
                    }

                    VStack(alignment: .leading, spacing: 16) {

                        Text("Net balance")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(theme.primaryText)

                        Text(
                            GhafFormat.money(
                                totalIncome - totalExpenses,
                                currency: settings.currency
                            )
                        )
                        .font(GhafTypeScale.largeTitle)
                        .foregroundStyle(theme.primaryText)

                        Text("Income minus recorded expenses this month.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        theme.surface,
                        in: RoundedRectangle(cornerRadius: 22)
                    )

                    categoryChart

                    categoryList
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func summaryCard(
        title: String,
        amount: Decimal,
        color: Color
    ) -> some View {

        VStack(alignment: .leading, spacing: 12) {

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.secondaryText)

            Text(
                GhafFormat.money(
                    amount,
                    currency: settings.currency
                )
            )
            .font(.system(size: 19, weight: .heavy))
            .foregroundStyle(color)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.surface,
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private var categoryChart: some View {

        VStack(alignment: .leading, spacing: 16) {

            Text("Spending by category")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

            if categoryTotals.isEmpty {

                Text("No spending data for this month.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(30)

            } else {

                Chart(categoryTotals) { item in

                    BarMark(
                        x: .value("Category", item.category),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(theme.accent)
                    .cornerRadius(6)
                }
                .frame(height: 230)
                .chartYAxisLabel(settings.currency)
                .chartXAxis {
                    AxisMarks(
                        values: .automatic
                    ) { value in

                        AxisValueLabel()
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
        .padding(20)
        .background(
            theme.surface,
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var categoryList: some View {

        VStack(alignment: .leading, spacing: 15) {

            Text("Category breakdown")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

            ForEach(categoryTotals) { item in

                HStack {

                    Text(item.category)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text(
                        GhafFormat.money(
                            Decimal(item.amount),
                            currency: settings.currency
                        )
                    )
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                }
            }
        }
        .padding(20)
        .background(
            theme.surface,
            in: RoundedRectangle(cornerRadius: 22)
        )
    }
}
