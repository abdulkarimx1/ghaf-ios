import Foundation
import UserNotifications

@MainActor
enum GhafSubscriptionReminderService {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ subscription: GhafSubscription, language: String) {
        let center = UNUserNotificationCenter.current()
        let id = "ghaf.subscription.\(subscription.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard subscription.isActive,
              let reminderDate = Calendar.current.date(byAdding: .day, value: -subscription.reminderDays, to: subscription.nextPaymentDate),
              reminderDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = language == "ar" ? "موعد اشتراك قريب" : "Subscription coming up"
        let amount = NSDecimalNumber(decimal: subscription.amount).stringValue
        content.body = language == "ar"
            ? "سيتم تجديد \(subscription.name) بمبلغ \(amount) \(subscription.currency)."
            : "\(subscription.name) renews for \(amount) \(subscription.currency)."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    static func cancel(_ subscription: GhafSubscription) {
        cancel(id: subscription.id)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ghaf.subscription.\(id.uuidString)"])
    }
}
