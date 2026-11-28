import Foundation

enum GhafActivityCounts {
    static func reviewQueue(_ transactions: [GhafTransaction]) -> Int {
        transactions.filter(\.needsReview).count
    }

    static func dueSoon(_ subscriptions: [GhafSubscription], date: Date = GhafClock.now) -> [GhafSubscription] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
        return subscriptions.filter {
            $0.isActive && !$0.needsConfirmation && $0.nextPaymentDate >= date && $0.nextPaymentDate <= end
        }
    }

    static func budgetAlerts(settings: GhafSettings, transactions: [GhafTransaction], date: Date = GhafClock.now) -> Int {
        BudgetCalculator.snapshot(settings: settings, transactions: transactions, date: date).status == .comfortable ? 0 : 1
    }
}
