import Foundation
import GhafCore

struct BudgetSnapshot {
    let limit: Decimal
    let spent: Decimal
    let remaining: Decimal
    let progress: Double
    let status: GhafBudgetStatus
    let periodTitle: String

    var hasBudget: Bool { limit > 0 }
}

enum BudgetCalculator {
    static func snapshot(
        settings: GhafSettings,
        transactions: [GhafTransaction],
        date: Date = .now
    ) -> BudgetSnapshot {
        let calendar = Calendar.current
        let currencyDebits = transactions.filter {
            $0.currency == settings.currency && $0.isExpense
        }

        let salaryDay = settings.salaryEnabled == true ? settings.salaryDay : nil
        let periodStart: Date
        let periodDays: Int

        if let salaryDay {
            periodStart = GhafSalaryCycle.startDate(for: date, salaryDay: salaryDay)
            periodDays = GhafSalaryCycle.daysInCycle(for: date, salaryDay: salaryDay)
        } else {
            let components = calendar.dateComponents([.year, .month], from: date)
            periodStart = calendar.date(from: components) ?? date
            periodDays = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        }

        if settings.budgetMode == "Category" {
            let budgets = settings.categoryBudgets
            let limit = budgets.values.reduce(Decimal.zero, +)
            let spent = currencyDebits
                .filter {
                    $0.date >= periodStart &&
                    $0.date <= date &&
                    budgets[$0.category] != nil
                }
                .reduce(Decimal.zero) { $0 + $1.spendingAmount }

            return makeSnapshot(
                limit: limit,
                spent: spent,
                periodTitle: salaryDay == nil ? "Remaining this month" : "Remaining this salary cycle"
            )
        }

        let salaryCurrency = settings.salaryCurrency ?? settings.currency
        let expectedIncome = settings.salaryEnabled == true && salaryCurrency == settings.currency
            ? (settings.salaryAmount ?? settings.monthlyIncome)
            : settings.monthlyIncome
        let availableIncome = max(expectedIncome - settings.fixedCommitments, Decimal.zero)
        let dailyLimit = availableIncome / Decimal(max(periodDays, 1))

        let spentToday = currencyDebits
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(Decimal.zero) { $0 + $1.spendingAmount }

        return makeSnapshot(
            limit: dailyLimit,
            spent: spentToday,
            periodTitle: "Remaining today"
        )
    }

    private static func makeSnapshot(
        limit: Decimal,
        spent: Decimal,
        periodTitle: String
    ) -> BudgetSnapshot {
        let remaining = limit - spent
        let ratio: Double = limit > 0
            ? NSDecimalNumber(decimal: spent / limit).doubleValue
            : (spent > 0 ? 1 : 0)

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
    private static func locale(for currency: String, languageCode: String) -> Locale {
        let regions: [String: String] = [
            "AED": "AE", "SAR": "SA", "KWD": "KW", "BHD": "BH",
            "OMR": "OM", "QAR": "QA", "USD": "US", "EUR": "DE", "GBP": "GB"
        ]
        let region = regions[currency.uppercased()] ?? "AE"
        return Locale(identifier: "\(languageCode == "ar" ? "ar" : "en")_\(region)")
    }

    static func symbol(for currency: String, languageCode: String = "en") -> String {
        switch currency.uppercased() {
        case "AED": return "\u{20C3}"
        case "SAR": return "\u{20C1}"
        case "OMR": return "\u{20C4}"
        case "KWD": return "د.ك"
        case "BHD": return "د.ب"
        case "QAR": return "ر.ق"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currency.uppercased()
            formatter.locale = locale(for: currency, languageCode: languageCode)
            let symbol = formatter.currencySymbol ?? ""
            return symbol.isEmpty || symbol == currency.uppercased()
                ? currency.uppercased()
                : symbol
        }
    }

    static let hideBalancesKey = "ghaf.hideBalances"
    static var balancesHidden: Bool { UserDefaults.standard.bool(forKey: hideBalancesKey) }

    static func hiddenMoney(_ amount: Decimal, currency: String, languageCode: String) -> String {
        let formatter = GhafMoneyLabel.formatter(languageCode: languageCode, currency: currency)
        let number = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return HiddenAmountMask.string(from: number)
    }

    /// `money`, or stars while balances are hidden. For text on screen; notifications and exports use `money`.
    static func shownMoney(_ amount: Decimal, currency: String, languageCode: String = "en") -> String {
        balancesHidden ? "\(currency) \(hiddenMoney(amount, currency: currency, languageCode: languageCode))"
            : money(amount, currency: currency, languageCode: languageCode)
    }

    static func money(
        _ amount: Decimal,
        currency: String,
        languageCode: String = "en"
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.locale = locale(for: currency, languageCode: languageCode)
        formatter.maximumFractionDigits = GhafCurrencyDigits.fractionDigits(for: currency)
        formatter.minimumFractionDigits = GhafCurrencyDigits.fractionDigits(for: currency)

        return formatter.string(from: amount as NSDecimalNumber)
            ?? "\(symbol(for: currency, languageCode: languageCode)) \(NSDecimalNumber(decimal: amount))"
    }

    static func decimal(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }
}
