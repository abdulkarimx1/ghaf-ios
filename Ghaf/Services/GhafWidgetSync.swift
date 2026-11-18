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
    static private(set) var lastChannels: (group: Bool, keychain: Bool)?

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
                           lastPurchase: last.map { .init(merchant: $0.merchant ?? GhafLocalization.category($0.category, languageCode: settings.languageCode),
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
        lastChannels = snapshot.save()
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
            merchant: transaction.merchant ?? GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en"),
            amount: transaction.amount, currency: transaction.currency, isCredit: transaction.direction == "credit",
            accountName: account?.name, balance: GhafFormat.balancesHidden ? nil : balance, needsReview: needsReview,
            symbol: GhafCategoryIcon.builtIn(transaction.category)?.symbol ?? (transaction.direction == "credit" ? "arrow.down" : "bag.fill"),
            category: GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en"))
        // The Dynamic Island is always dark, so it takes the theme's dark-mode colours.
        let settings = try? GhafPersistence.settings(in: GhafPersistence.shared().mainContext)
        let theme = GhafTheme.resolve(name: settings?.themeName ?? "Abu Dhabi", appearanceMode: "Dark", systemIsDark: true)
        _ = try? Activity.request(attributes: GhafPurchaseAttributes(arabic: arabic, accent: hex(theme.accent), glow: hex(theme.glow)),
                                  content: .init(state: state, staleDate: .now.addingTimeInterval(15 * 60)))
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
