import Foundation
import SwiftData
import WidgetKit
import ActivityKit
import SwiftUI
import UIKit

/// Keeps the widgets and the purchase Live Activity in step with the ledger.
@MainActor
enum GhafWidgetSync {
    static let liveActivityKey = "ghaf.liveActivity"
    /// Which channels the last refresh could write, shown in Notifications & widgets so a broken install is visible.
    static private(set) var lastChannels: (group: Bool, keychain: Bool)? = {
        guard let values = UserDefaults.standard.dictionary(forKey: "ghaf.widget.channels"),
              let group = values["group"] as? Bool, let keychain = values["keychain"] as? Bool else { return nil }
        return (group, keychain)
    }()

    /// Recomputes what the widgets show and asks WidgetKit to redraw them.
    static func refresh(context: ModelContext) {
        guard let settings = try? GhafPersistence.settings(in: context),
              let transactions = try? context.fetch(FetchDescriptor<GhafTransaction>()),
              let accounts = try? context.fetch(FetchDescriptor<GhafAccount>()) else { return }
        let currency = settings.currency
        let calendar = GhafCalendar.current
        let active = accounts.filter { !$0.isArchived && $0.includeInTotal }
        let balance = GhafAccountBalanceCalculator.balancesByCurrency(accounts: active, transactions: transactions)
            .first { $0.currency == currency }?.amount
        let spending = transactions.filter { $0.currency == currency && $0.isExpense }
        let today = spending.filter { calendar.isDateInToday($0.date) }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        let month = spending.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(Decimal.zero) { $0 + $1.spendingAmount }
        let last = transactions.filter { $0.direction == "debit" && $0.isSpendingOrIncome }.max { $0.date < $1.date }
        let todays = spending.filter { calendar.isDateInToday($0.date) }
        let byCategory = Dictionary(grouping: todays) { GhafLocalization.category($0.category, languageCode: settings.languageCode) }
            .map { GhafWidgetSnapshot.CategorySpend(name: $0.key, amount: $0.value.reduce(Decimal.zero) { $0 + $1.spendingAmount }) }
            .sorted { $0.amount > $1.amount }
        let startOfToday = calendar.startOfDay(for: .now)
        let week: [Decimal] = (0..<7).reversed().map { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: startOfToday) else { return 0 }
            return spending.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        }
        var snapshot = GhafWidgetSnapshot(currency: currency, balance: balance, spentToday: today, spentThisMonth: month,
                           lastPurchase: last.map { .init(merchant: GhafFormat.balancesHidden ? GhafLocalization.category($0.category, languageCode: settings.languageCode) : ($0.merchant ?? GhafLocalization.category($0.category, languageCode: settings.languageCode)),
                                                          amount: $0.amount, currency: $0.currency, date: $0.date) },
                           hidden: GhafFormat.balancesHidden, arabic: settings.languageCode == "ar", updated: .now)
        snapshot.todayCategories = Array(byCategory.prefix(4))
        snapshot.lastSevenDays = week
        let budget = BudgetCalculator.snapshot(settings: settings, transactions: transactions)
        if settings.budgetMode != "Category", budget.hasBudget {
            snapshot.dailyBudgetUsed = NSDecimalNumber(decimal: budget.spent / budget.limit).doubleValue
        }
        let lit = GhafTheme.resolve(name: settings.themeName, appearanceMode: "Dark", systemIsDark: true)
        snapshot.accent = hex(lit.accent)
        snapshot.glow = hex(lit.glow)

        let language = settings.languageCode
        let name = { (category: String) in GhafLocalization.category(category, languageCode: language) }
        snapshot.day = period(.day, slices: 8, slice: (.hour, 3), spending: spending, calendar: calendar, name: name)
        snapshot.week = period(.weekOfYear, slices: 7, slice: (.day, 1), spending: spending, calendar: calendar, name: name)
        snapshot.month = period(.month, slices: 5, slice: (.day, 7), spending: spending, calendar: calendar, name: name)

        if let latest = transactions.max(by: { $0.createdAt < $1.createdAt }) {
            snapshot.recent = .init(merchant: GhafFormat.balancesHidden ? name(latest.category) : latest.merchant, category: name(latest.category),
                                    symbol: GhafCategoryIcon.builtIn(latest.category)?.symbol ?? (latest.direction == "credit" ? "arrow.down" : "bag.fill"),
                                    amount: latest.amount, currency: latest.currency, date: latest.date,
                                    isCredit: latest.direction == "credit",
                                    account: GhafFormat.balancesHidden ? nil : accounts.first { $0.id == latest.accountID }?.name,
                                    bank: GhafFormat.balancesHidden ? nil : latest.bank, needsReview: latest.needsReview)
        }

        if budget.hasBudget {
            let ar = language == "ar"
            let daily = settings.budgetMode != "Category"
            let end: Date
            if daily {
                end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            } else if settings.salaryEnabled == true, let salaryDay = settings.salaryDay {
                let start = GhafSalaryCycle.startDate(for: .now, salaryDay: salaryDay)
                end = calendar.date(byAdding: .day, value: GhafSalaryCycle.daysInCycle(for: .now, salaryDay: salaryDay), to: start) ?? start
            } else {
                end = calendar.dateInterval(of: .month, for: .now)?.end ?? startOfToday
            }
            snapshot.budget = .init(limit: budget.limit, spent: budget.spent,
                                    title: daily ? (ar ? "ميزانية اليوم" : "Today's budget") : (ar ? "ميزانية الشهر" : "Monthly budget"),
                                    end: end)
        }

        if let subscriptions = try? context.fetch(FetchDescriptor<GhafSubscription>()) {
            snapshot.upcoming = subscriptions.filter(\.isActive).sorted { $0.nextPaymentDate < $1.nextPaymentDate }.prefix(6)
                .map { .init(name: $0.name, amount: $0.amount, currency: $0.currency, date: $0.nextPaymentDate,
                             symbol: GhafCategoryIcon.builtIn($0.category)?.symbol ?? "repeat") }
        }
        lastChannels = snapshot.save()
        UserDefaults.standard.set(["group": lastChannels?.group ?? false, "keychain": lastChannels?.keychain ?? false],
                                  forKey: "ghaf.widget.channels")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Shows a purchase on the Lock Screen and in the Dynamic Island. One at a time: a new purchase
    /// replaces the previous one, and each goes stale after 15 minutes.
    static func showPurchase(_ transaction: GhafTransaction, account: GhafAccount?, balance: Decimal?,
                             needsReview: Bool, arabic: Bool) async {
        guard UserDefaults.standard.object(forKey: liveActivityKey) as? Bool ?? true,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await endAll()
        let state = GhafPurchaseAttributes.ContentState(
            merchant: GhafFormat.balancesHidden ? GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en") : (transaction.merchant ?? GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en")),
            amount: transaction.amount, currency: transaction.currency, isCredit: transaction.direction == "credit",
            accountName: GhafFormat.balancesHidden ? nil : account?.name, balance: GhafFormat.balancesHidden ? nil : balance, needsReview: needsReview,
            symbol: GhafCategoryIcon.builtIn(transaction.category)?.symbol ?? (transaction.direction == "credit" ? "arrow.down" : "bag.fill"),
            category: GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en"),
            recordedAt: .now, hidden: GhafFormat.balancesHidden)
        // The Dynamic Island is always dark, so it takes the theme's dark-mode colours.
        let settings = try? GhafPersistence.settings(in: GhafPersistence.shared().mainContext)
        let theme = GhafTheme.resolve(name: settings?.themeName ?? "Abu Dhabi", appearanceMode: "Dark", systemIsDark: true)
        _ = try? Activity.request(attributes: GhafPurchaseAttributes(arabic: arabic, accent: hex(theme.accent), glow: hex(theme.glow)),
                                  content: .init(state: state, staleDate: .now.addingTimeInterval(15 * 60)))
    }

    /// Spending in the current day/week/month (main currency, transfers excluded by `isExpense`), cut into
    /// equal slices for the widget bars, plus the whole previous period for comparison.
    private static func period(_ unit: Calendar.Component, slices: Int, slice: (Calendar.Component, Int),
                               spending: [GhafTransaction], calendar: Calendar,
                               name: (String) -> String) -> GhafWidgetSnapshot.Period? {
        guard let now = calendar.dateInterval(of: unit, for: .now),
              let before = calendar.date(byAdding: unit, value: -1, to: now.start),
              let previous = calendar.dateInterval(of: unit, for: before) else { return nil }
        let inside = spending.filter { now.contains($0.date) && $0.date < now.end }
        let sum = { (items: [GhafTransaction]) in items.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
        let bars: [Decimal] = (0..<slices).map { index in
            guard let from = calendar.date(byAdding: slice.0, value: index * slice.1, to: now.start),
                  let to = calendar.date(byAdding: slice.0, value: (index + 1) * slice.1, to: now.start) else { return 0 }
            return sum(inside.filter { $0.date >= from && $0.date < to })
        }
        let categories = Dictionary(grouping: inside, by: \.category)
            .map { GhafWidgetSnapshot.CategorySpend(name: name($0.key), amount: sum($0.value),
                                                    symbol: GhafCategoryIcon.builtIn($0.key)?.symbol) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
        return .init(end: now.end, spent: sum(inside),
                     previous: sum(spending.filter { $0.date >= previous.start && $0.date < previous.end }),
                     count: inside.filter { $0.spendingAmount > 0 }.count, bars: bars, categories: Array(categories.prefix(5)))
    }

    private static func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(max(0, min(255, r * 255))) << 16 | UInt32(max(0, min(255, g * 255))) << 8 | UInt32(max(0, min(255, b * 255)))
    }

    /// Purchases are moments, not ongoing events: clear old ones when Ghaf opens or a new one arrives.
    static func endAll() async {
        for activity in Activity<GhafPurchaseAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func endStale() async {
        for activity in Activity<GhafPurchaseAttributes>.activities where activity.content.staleDate.map({ $0 < .now }) ?? false {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
