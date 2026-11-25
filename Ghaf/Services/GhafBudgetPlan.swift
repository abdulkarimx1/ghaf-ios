import Foundation
import GhafCore

/// The Budget screen's category numbers (spend, user or suggested budget), shared with the widget snapshot
/// so both read one calculation. Moved out of GhafBudgetView unchanged.
struct GhafBudgetPlan {
    let settings: GhafSettings
    let transactions: [GhafTransaction]
    let calendar: Calendar
    let now: Date

    private var currency: String { settings.currency }
    var hasSalary: Bool { settings.salaryEnabled == true && settings.salaryDay != nil }
    var preset: BudgetAllocation.Preset { BudgetAllocation.Preset(rawValue: settings.allocationPresetRaw) ?? .balanced }

    /// Income for the budget period: the salary when it's set up, else the monthly income from Settings.
    var income: Decimal {
        settings.salaryEnabled == true ? (settings.salaryAmount ?? settings.monthlyIncome) : settings.monthlyIncome
    }
    var incomeCurrency: String {
        settings.salaryEnabled == true ? (settings.salaryCurrency ?? settings.currency) : settings.currency
    }
    var salaryCurrencyMismatch: Bool { hasSalary && incomeCurrency != currency }
    var allocationIncome: Decimal { salaryCurrencyMismatch ? settings.monthlyIncome : income }

    /// The salary cycle when a salary day is set, else this calendar month (same rule as BudgetCalculator).
    var cycle: DateInterval {
        if hasSalary, let day = settings.salaryDay {
            let start = GhafSalaryCycle.startDate(for: now, salaryDay: day)
            return DateInterval(start: start, end: GhafSalaryCycle.nextSalaryDate(after: now, salaryDay: day))
        }
        return calendar.dateInterval(of: .month, for: now)!
    }

    func expenses(in range: DateInterval) -> [GhafTransaction] {
        transactions.filter { transaction in
            guard transaction.currency == currency, transaction.isExpense, range.contains(transaction.date) else { return false }
            return !CategoryTaxonomy.isTransferOrAdjustment(category: transaction.category, subcategory: transaction.subcategory)
                && CategoryTaxonomy.category(named: transaction.category)?.isIncome != true
        }
    }

    var categoryRows: [(name: String, spent: Decimal, budget: Decimal)] {
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

    func roundedBudget(_ amount: Decimal) -> Decimal {
        var result = Decimal.zero, value = amount
        NSDecimalRound(&result, &value, GhafCurrencyDigits.fractionDigits(for: currency), .plain)
        return result
    }
}
