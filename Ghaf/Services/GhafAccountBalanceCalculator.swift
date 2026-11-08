import Foundation
import SwiftData

struct GhafCurrencyBalance: Identifiable {
    let currency: String
    let amount: Decimal
    var id: String { currency }
}

enum GhafAccountBalanceCalculator {
    static func balance(
        for account: GhafAccount,
        transactions: [GhafTransaction]
    ) -> Decimal {
        let activity = transactions
            .filter {
                $0.accountID == account.id &&
                $0.currency == account.currency &&
                $0.date >= account.openingDate
            }
            .reduce(Decimal.zero) { total, transaction in
                if transaction.direction == "credit" {
                    return total + transaction.amount
                }
                if transaction.direction == "debit" {
                    return total - transaction.amount
                }
                return total
            }
        return account.openingBalance + activity
    }

    static func balancesByCurrency(
        accounts: [GhafAccount],
        transactions: [GhafTransaction]
    ) -> [GhafCurrencyBalance] {
        let active = accounts.filter { !$0.isArchived }
        let grouped = Dictionary(grouping: active, by: \.currency)
        return grouped.map { currency, values in
            GhafCurrencyBalance(
                currency: currency,
                amount: values.reduce(Decimal.zero) {
                    $0 + balance(for: $1, transactions: transactions)
                }
            )
        }
        .sorted { $0.currency < $1.currency }
    }

    static func matchAccount(
        bank: String?,
        sender: String?,
        accounts: [GhafAccount]
    ) -> GhafAccount? {
        let incoming = [bank, sender]
            .compactMap { $0 }
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return nil }

        // Account names are user-defined. A card wallet may be labelled
        // "iVESTOR" while its account type is still Cash or Prepaid.
        // Match names across all active accounts, but prefer real bank accounts
        // when scores are otherwise equal.
        let bankAccounts = accounts.filter { !$0.isArchived }

        let ranked = bankAccounts.map { account -> (GhafAccount, Int) in
            let institution = normalize(account.institution ?? "")
            let name = normalize(account.name)
            var score = 0

            for value in incoming {
                if !institution.isEmpty && value == institution { score = max(score, 100) }
                if !name.isEmpty && value == name {
                    score = max(score, account.type.isBankAccount ? 100 : 95)
                }
                if !institution.isEmpty && value.contains(institution) { score = max(score, 80) }
                if !institution.isEmpty && institution.contains(value) { score = max(score, 70) }
                if !name.isEmpty && value.contains(name) { score = max(score, 65) }
            }
            return (account, score)
        }

        return ranked
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 { return $0.0.isPrimary && !$1.0.isPrimary }
                return $0.1 > $1.1
            }
            .first?.0
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

enum GhafSalaryCycle {
    static func startDate(
        for date: Date,
        salaryDay: Int,
        calendar: Calendar = .current
    ) -> Date {
        let currentDay = calendar.component(.day, from: date)
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let effectiveSalaryDay = min(max(salaryDay, 1), daysInMonth)
        let offset = currentDay < effectiveSalaryDay ? -1 : 0
        let base = calendar.date(byAdding: .month, value: offset, to: date) ?? date
        return dateInMonth(containing: base, day: salaryDay, calendar: calendar)
    }

    static func nextSalaryDate(
        after date: Date,
        salaryDay: Int,
        calendar: Calendar = .current
    ) -> Date {
        let start = startDate(for: date, salaryDay: salaryDay, calendar: calendar)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return dateInMonth(containing: nextMonth, day: salaryDay, calendar: calendar)
    }

    static func periodKey(
        for date: Date,
        salaryDay: Int,
        calendar: Calendar = .current
    ) -> String {
        let start = startDate(for: date, salaryDay: salaryDay, calendar: calendar)
        let components = calendar.dateComponents([.year, .month], from: start)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func daysInCycle(
        for date: Date,
        salaryDay: Int,
        calendar: Calendar = .current
    ) -> Int {
        let start = startDate(for: date, salaryDay: salaryDay, calendar: calendar)
        let end = nextSalaryDate(after: start, salaryDay: salaryDay, calendar: calendar)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 30, 1)
    }

    private static func dateInMonth(
        containing date: Date,
        day: Int,
        calendar: Calendar
    ) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let month = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: month) else { return date }
        var result = components
        result.day = min(max(day, 1), range.count)
        result.hour = 0
        result.minute = 0
        result.second = 0
        return calendar.date(from: result) ?? date
    }
}
