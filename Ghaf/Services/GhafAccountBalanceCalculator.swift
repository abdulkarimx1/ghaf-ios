import Foundation
import SwiftData
import GhafCore

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

    /// Every account's balance in one pass over the transactions; same rules as `balance(for:)`.
    static func balances(
        accounts: [GhafAccount],
        transactions: [GhafTransaction]
    ) -> [UUID: Decimal] {
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = Dictionary(uniqueKeysWithValues: byID.map { ($0.key, $0.value.openingBalance) })
        for transaction in transactions {
            guard let id = transaction.accountID, let account = byID[id] else { continue }
            let direction = transaction.direction
            guard direction == "credit" || direction == "debit",
                  transaction.currency == account.currency,
                  transaction.date >= account.openingDate else { continue }
            result[id, default: 0] += direction == "credit" ? transaction.amount : -transaction.amount
        }
        return result
    }

    static func balancesByCurrency(
        accounts: [GhafAccount],
        transactions: [GhafTransaction]
    ) -> [GhafCurrencyBalance] {
        balancesByCurrency(accounts: accounts, balances: balances(accounts: accounts, transactions: transactions))
    }

    static func balancesByCurrency(
        accounts: [GhafAccount],
        balances: [UUID: Decimal]
    ) -> [GhafCurrencyBalance] {
        let active = accounts.filter { !$0.isArchived && $0.includeInTotal }
        let grouped = Dictionary(grouping: active, by: \.currency)
        return grouped.map { currency, values in
            GhafCurrencyBalance(
                currency: currency,
                amount: values.reduce(Decimal.zero) { $0 + (balances[$1.id] ?? $1.openingBalance) }
            )
        }
        .sorted { $0.currency < $1.currency }
    }

    @MainActor
    static func matchAccount(
        bank: String?,
        sender: String?,
        accounts: [GhafAccount],
        accountRef: String? = nil,
        cardPurchase: Bool = false
    ) -> GhafAccount? {
        let active = accounts.filter { !$0.isArchived }
        if GhafAccountMappings.hasConflictingReference(bank: bank, sender: sender, accountRef: accountRef) { return nil }
        if let learned = GhafAccountMappings.exactAccountID(bank: bank, sender: sender, accountRef: accountRef),
           let account = active.first(where: { $0.id == learned }) { return account }
        if let accountRef {
            let suffix = String(accountRef.filter(\.isNumber).suffix(4))
            let matches = active.filter { $0.cardLast4 == suffix }
            if matches.count == 1 { return matches[0] }
        }
        if let learnedID = GhafAccountMappings.bankOnlyAccountID(bank: bank, sender: sender, accountRef: accountRef),
           let learned = active.first(where: { $0.id == learnedID }),
           accountRef == nil || (learned.cardLast4 ?? "").isEmpty {
            return learned
        }
        // A card purchase can't come from a savings account with no card on it, so it can't tie with the card's account.
        let eligible = cardPurchase ? active.filter { $0.type != .savings || !($0.cardLast4 ?? "").isEmpty } : active
        let candidates = eligible.map {
            AccountCandidate(id: $0.id, name: $0.name, institution: $0.institution,
                             isBankAccount: $0.type.isBankAccount, isPrimary: $0.isPrimary)
        }
        guard let id = AccountMatcher.match(bank: bank, sender: sender, candidates: candidates) else { return nil }
        return active.first { $0.id == id }
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
