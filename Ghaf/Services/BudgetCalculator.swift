
import Foundation
import GhafCore

struct BudgetSnapshot {

    let limit: Decimal
    let spent: Decimal
    let remaining: Decimal
    let progress: Double
    let status: GhafBudgetStatus
    let periodTitle: String

    var hasBudget: Bool {
        limit > 0
    }
}

enum BudgetCalculator {

    static func snapshot(
        settings: GhafSettings,
        transactions: [GhafTransaction],
        date: Date = Date()
    ) -> BudgetSnapshot {

        let currencyTransactions = transactions.filter {
            $0.currency == settings.currency &&
            $0.direction == TransactionDirection.debit.rawValue
        }

        if settings.budgetMode == "Category" {

            let budgets = settings.categoryBudgets

            let limit = budgets.values.reduce(Decimal.zero, +)

            let monthlyTransactions = currencyTransactions.filter {
                Calendar.current.isDate(
                    $0.date,
                    equalTo: date,
                    toGranularity: .month
                )
            }

            let spent = monthlyTransactions
                .filter { budgets[$0.category] != nil }
                .reduce(Decimal.zero) {
                    $0 + $1.amount
                }

            return makeSnapshot(
                limit: limit,
                spent: spent,
                periodTitle: "Remaining this month"
            )
        }

        let availableIncome =
            settings.monthlyIncome - settings.fixedCommitments

        let monthlyAvailable = availableIncome > 0
            ? availableIncome
            : Decimal.zero

        let daysInMonth = Calendar.current.range(
            of: .day,
            in: .month,
            for: date
        )?.count ?? 30

        let dailyLimit = monthlyAvailable / Decimal(daysInMonth)

        let spent = currencyTransactions
            .filter {
                Calendar.current.isDate(
                    $0.date,
                    inSameDayAs: date
                )
            }
            .reduce(Decimal.zero) {
                $0 + $1.amount
            }

        return makeSnapshot(
            limit: dailyLimit,
            spent: spent,
            periodTitle: "Remaining today"
        )
    }

    private static func makeSnapshot(
        limit: Decimal,
        spent: Decimal,
        periodTitle: String
    ) -> BudgetSnapshot {

        let remaining = limit - spent

        let ratio: Double

        if limit > 0 {

            ratio = NSDecimalNumber(
                decimal: spent / limit
            ).doubleValue

        } else {

            ratio = spent > 0 ? 1.0 : 0.0
        }

        let status: GhafBudgetStatus

        if spent > limit && limit > 0 {
            status = .over
        } else if ratio >= 0.80 {
            status = .close
        } else {
            status = .comfortable
        }

        return BudgetSnapshot(
            limit: limit,
            spent: spent,
            remaining: remaining,
            progress: min(max(ratio, 0), 1),
            status: status,
            periodTitle: periodTitle
        )
    }
}

enum GhafFormat {

    static func money(
        _ amount: Decimal,
        currency: String
    ) -> String {

        let formatter = NumberFormatter()

        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: "en_AE")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        return formatter.string(
            from: amount as NSDecimalNumber
        ) ?? "\(currency) \(NSDecimalNumber(decimal: amount))"
    }

    static func decimal(_ amount: Decimal) -> String {

        return NSDecimalNumber(
            decimal: amount
        ).stringValue
    }
}
