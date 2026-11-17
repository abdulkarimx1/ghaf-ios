import Foundation
import SwiftData
import UserNotifications

/// Optional summaries from the ledger: a morning note (yesterday's spending), an evening note (today's),
/// a weekly note on the first day of the user's week, and a note each time an automation adds a
/// transaction. Every number is computed from recorded transactions in the main currency only.
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
        // A new transaction note is on unless turned off; the summaries are opt-in.
        UserDefaults.standard.object(forKey: key) as? Bool ?? (key == autoTransactionKey)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Recomputes and schedules the next morning, evening and weekly notes.
    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard isOn(morningKey) || isOn(eveningKey) || isOn(weeklyKey),
              let settings = try? GhafPersistence.settings(in: context),
              let transactions = try? context.fetch(FetchDescriptor<GhafTransaction>()) else { return }
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

    /// Right after an automation records a transaction: what was added and the account's ledger balance.
    static func transactionAdded(_ transaction: GhafTransaction, account: GhafAccount?, balance: Decimal?,
                                 needsReview: Bool, languageCode: String) {
        guard isOn(autoTransactionKey) else { return }
        let ar = languageCode == "ar"
        let amount = GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: languageCode)
        let place = transaction.merchant.map { ar ? " · \($0)" : " · \($0)" } ?? ""
        let content = UNMutableNotificationContent()
        content.title = (transaction.direction == "credit" ? (ar ? "إيداع " : "Received ") : (ar ? "صرف " : "Spent ")) + amount + place
        var lines: [String] = []
        if let account, let balance {
            lines.append(ar ? "رصيد \(account.name): \(GhafFormat.money(balance, currency: account.currency, languageCode: languageCode))"
                            : "\(account.name) balance: \(GhafFormat.money(balance, currency: account.currency, languageCode: languageCode))")
        }
        if needsReview { lines.append(ar ? "يحتاج مراجعة في غاف." : "Needs a quick review in Ghaf.") }
        content.body = lines.isEmpty ? (ar ? "أُضيفت إلى غاف." : "Added to Ghaf.") : lines.joined(separator: "\n")
        // One note per transaction: a repeated automation run reuses the identifier.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ghaf.added.\(transaction.id.uuidString)",
                                                                     content: content, trigger: nil))
    }
}
