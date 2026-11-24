import Foundation
import SwiftData
import UserNotifications
import GhafCore

/// Optional scheduled summaries from the ledger. Event alerts are handled by GhafEventNotifications.
///
/// iOS cannot compute a notification's text when it fires, so each summary is scheduled for its next
/// time with the numbers known now, and rescheduled whenever a transaction arrives or Ghaf opens.
@MainActor
enum GhafDigestNotifications {
    static let morningKey = "ghaf.notify.morning"
    static let eveningKey = "ghaf.notify.evening"
    static let weeklyKey = "ghaf.notify.weekly"
    static let autoTransactionKey = "ghaf.notify.autoTransaction"

    private static let ids = ["ghaf.digest.morning", "ghaf.digest.evening", "ghaf.digest.weekly"]

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? (key == autoTransactionKey)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Recomputes and schedules the next morning, evening and weekly notes.
    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard let settings = try? GhafPersistence.settings(in: context),
              let transactions = try? context.fetch(FetchDescriptor<GhafTransaction>()) else { return }
        updateEvents(context: context, settings: settings, transactions: transactions)
        guard isOn(morningKey) || isOn(eveningKey) || isOn(weeklyKey) else { return }
        let ar = settings.languageCode == "ar"
        let currency = settings.currency
        let calendar = GhafCalendar.current
        let now = Date.now
        func spent(_ interval: DateInterval) -> Decimal {
            transactions.filter { $0.currency == currency && $0.isExpense && interval.contains($0.date) }
                .reduce(Decimal.zero) { $0 + $1.spendingAmount }
        }
        func money(_ value: Decimal) -> String { GhafFormat.money(value, currency: currency, languageCode: settings.languageCode) }
        func next(hour: Int, weekday: Int? = nil) -> DateComponents {
            var components = DateComponents(hour: hour, minute: 0)
            components.weekday = weekday
            let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
        func schedule(_ id: String, _ title: String, _ body: String, _ when: DateComponents) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil
            center.add(UNNotificationRequest(identifier: id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }

        let today = calendar.dateInterval(of: .day, for: now)!
        if isOn(eveningKey) {
            let total = spent(today)
            let count = transactions.filter { $0.isExpense && today.contains($0.date) }.count
            schedule(ids[1], ar ? "ملخص اليوم" : "Today in Ghaf",
                     total > 0 ? (ar ? "صرفت \(money(total)) في \(count) عملية اليوم." : "You spent \(money(total)) across \(count) transactions today.")
                               : (ar ? "لم تسجّل أي مصروف اليوم." : "No spending recorded today."),
                     next(hour: 21))
        }
        if isOn(morningKey) {
            // The note fires tomorrow morning about today, unless it is still before 8 today.
            let morning = next(hour: 8)
            let fireDay = calendar.date(from: morning) ?? now
            let yesterday = calendar.dateInterval(of: .day, for: calendar.date(byAdding: .day, value: -1, to: fireDay)!)!
            let total = spent(yesterday)
            schedule(ids[0], ar ? "صباح الخير" : "Good morning",
                     total > 0 ? (ar ? "صرفت أمس \(money(total))." : "Yesterday you spent \(money(total)).")
                               : (ar ? "لم تصرف شيئاً أمس." : "Nothing spent yesterday."),
                     morning)
        }
        if isOn(weeklyKey) {
            // First day of the user's week (Saturday, Sunday or Monday, as chosen) at 9.
            let when = next(hour: 9, weekday: calendar.firstWeekday)
            let fireDay = calendar.date(from: when) ?? now
            let lastWeek = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: fireDay))!,
                                        end: calendar.startOfDay(for: fireDay))
            let before = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: lastWeek.start)!, end: lastWeek.start)
            let total = spent(lastWeek), previous = spent(before)
            var body = ar ? "صرفت الأسبوع الماضي \(money(total))." : "Last week you spent \(money(total))."
            if previous > 0 {
                body += total > previous ? (ar ? " أكثر من الأسبوع الذي قبله (\(money(previous)))." : " More than the week before (\(money(previous)))." )
                                         : (ar ? " أقل من الأسبوع الذي قبله (\(money(previous)))." : " Less than the week before (\(money(previous))).")
            }
            schedule(ids[2], ar ? "أسبوعك في غاف" : "Your week in Ghaf", body, when)
        }
    }

    /// Only a transaction held for review needs an event alert.
    static func transactionAdded(_ transaction: GhafTransaction, needsReview: Bool, languageCode: String, unusual: Bool = false) {
        guard needsReview else {
            GhafEventNotifications.recordCaptureBanner(transaction, languageCode: languageCode, unusual: unusual)
            return
        }
        let ar = languageCode == "ar"
        let amount = GhafFormat.balancesHidden
            ? GhafFormat.hiddenMoney(transaction.amount, currency: transaction.currency, languageCode: languageCode)
            : GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: languageCode)
        let merchant = GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant)
            ?? GhafLocalization.category(transaction.category, languageCode: languageCode)
        GhafEventNotifications.record(
            key: "transaction-review-\(transaction.id.uuidString)", kind: .transactionReview,
            title: ar ? "عملية تحتاج مراجعتك" : "Check a transaction",
            message: ar ? "راجع \(merchant) · \(amount) في الإشعارات." : "Review \(merchant) · \(amount) in Notifications.",
            itemID: transaction.id.uuidString,
            notifies: GhafEventNotifications.isEnabled(GhafEventNotifications.transactionReviewKey)
        )
    }

    private static func updateEvents(context: ModelContext, settings: GhafSettings, transactions: [GhafTransaction]) {
        let ar = settings.languageCode == "ar"
        let calendar = GhafCalendar.current
        let monthKey = "\(calendar.component(.year, from: .now))-\(calendar.component(.month, from: .now))"
        if let subscriptions = try? context.fetch(FetchDescriptor<GhafSubscription>()) {
            for subscription in subscriptions where subscription.needsConfirmation && subscription.createdAt > Date.now.addingTimeInterval(-120) {
                GhafEventNotifications.record(
                    key: "detected-subscription-\(subscription.id.uuidString)", kind: .detectedSubscription,
                    title: ar ? "اشتراك متكرر مرصود" : "Recurring charge detected",
                    message: ar ? "راجع \(subscription.name) قبل تتبّع الاشتراك." : "Review \(subscription.name) before tracking it.",
                    itemID: subscription.id.uuidString,
                    notifies: GhafEventNotifications.isEnabled(GhafEventNotifications.detectedSubscriptionKey)
                )
            }
        }

        guard let month = GhafCalendar.current.dateInterval(of: .month, for: .now) else { return }
        let monthly = transactions.filter {
            $0.currency == settings.currency && $0.isExpense && $0.date >= month.start && $0.date < month.end
        }
        let spent = Dictionary(grouping: monthly, by: \.category).mapValues {
            $0.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        }
        let latest = monthly.max(by: { $0.createdAt < $1.createdAt })
        func notifyThresholds(name: String, eventKey: String, total: Decimal, limit: Decimal, previous: Decimal) {
            guard limit > 0 else { return }
            for (threshold, label) in [(Decimal(string: "0.8")!, "80%"), (Decimal(1), "100%")] {
                if previous / limit < threshold && total / limit >= threshold {
                    let key = "budget-\(monthKey)-\(eventKey)-\(label)"
                    GhafEventNotifications.record(
                        key: key, kind: .budgetThreshold,
                        title: ar ? "بلغت \(name) \(label) من ميزانيتها" : "\(name) reached \(label) of its budget",
                        message: ar ? "وصل الصرف في \(name) إلى \(label) من ميزانية هذا الشهر." : "\(name) spending reached \(label) of its monthly budget.",
                        notifies: GhafEventNotifications.isEnabled(GhafEventNotifications.budgetThresholdKey)
                    )
                }
            }
        }
        if settings.budgetMode == "Category" {
            for (category, limit) in settings.categoryBudgets where limit > 0 {
                let total = spent[category, default: .zero]
                let key = "ghaf.budget.observed.\(monthKey).category.\(category)"
                let isLatest = latest.map { $0.category == category && Date.now.timeIntervalSince($0.createdAt) < 120 } ?? false
                let previous = UserDefaults.standard.string(forKey: key).flatMap { Decimal(string: $0) }
                    ?? (isLatest ? max(Decimal.zero, total - latest!.spendingAmount) : total)
                notifyThresholds(name: GhafLocalization.category(category, languageCode: settings.languageCode), eventKey: "category-\(category)", total: total, limit: limit, previous: previous)
                UserDefaults.standard.set(NSDecimalNumber(decimal: total).stringValue, forKey: key)
            }
        }

        let salaryCurrency = settings.salaryCurrency ?? settings.currency
        let monthlyIncome = settings.salaryEnabled == true && salaryCurrency == settings.currency
            ? (settings.salaryAmount ?? settings.monthlyIncome)
            : settings.monthlyIncome
        for bucket in [BudgetAllocation.Bucket.needs, .wants] where monthlyIncome > 0 {
            let name = ar ? (bucket == .needs ? "الاحتياجات" : "الرغبات") : (bucket == .needs ? "Needs" : "Wants")
            let key = "ghaf.budget.observed.\(monthKey).bucket.\(bucket.rawValue)"
            let total = monthly.filter { BudgetAllocation.bucket(forCategory: $0.category) == bucket }
                .reduce(Decimal.zero) { $0 + $1.spendingAmount }
            let isLatest = latest.map { BudgetAllocation.bucket(forCategory: $0.category) == bucket && Date.now.timeIntervalSince($0.createdAt) < 120 } ?? false
            let previous = UserDefaults.standard.string(forKey: key).flatMap { Decimal(string: $0) }
                ?? (isLatest ? max(Decimal.zero, total - latest!.spendingAmount) : total)
            notifyThresholds(name: name, eventKey: "bucket-\(bucket.rawValue)", total: total,
                             limit: monthlyIncome * BudgetAllocation.share(bucket), previous: previous)
            UserDefaults.standard.set(NSDecimalNumber(decimal: total).stringValue, forKey: key)
        }
    }
}
