import Foundation
import SwiftData
import WidgetKit
import ActivityKit

/// Keeps the widgets and the purchase Live Activity in step with the ledger.
@MainActor
enum GhafWidgetSync {
    static let liveActivityKey = "ghaf.liveActivity"

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
        GhafWidgetSnapshot(currency: currency, balance: balance, spentToday: today, spentThisMonth: month,
                           lastPurchase: last.map { .init(merchant: $0.merchant ?? GhafLocalization.category($0.category, languageCode: settings.languageCode),
                                                          amount: $0.amount, currency: $0.currency, date: $0.date) },
                           hidden: GhafFormat.balancesHidden, arabic: settings.languageCode == "ar", updated: .now).save()
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
            accountName: account?.name, balance: GhafFormat.balancesHidden ? nil : balance, needsReview: needsReview)
        _ = try? Activity.request(attributes: GhafPurchaseAttributes(arabic: arabic),
                                  content: .init(state: state, staleDate: .now.addingTimeInterval(15 * 60)))
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
