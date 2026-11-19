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
        guard GhafEventNotifications.isEnabled(GhafEventNotifications.subscriptionDueKey), subscription.isActive,
              let reminderDate = Calendar.current.date(byAdding: .day, value: -subscription.reminderDays, to: subscription.nextPaymentDate),
              reminderDate > .now else {
            GhafEventNotifications.removeFutureSubscriptionEvent(id: subscription.id)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = language == "ar" ? "موعد دفع قريب" : "Payment coming up"
        let amount = NSDecimalNumber(decimal: subscription.amount).stringValue
        content.body = language == "ar"
            ? "موعد دفع \(subscription.name) قريب · \(amount) \(subscription.currency)."
            : "\(subscription.name) is due soon · \(amount) \(subscription.currency)."
        content.sound = .default
        let eventKey = "subscription-due-\(subscription.id.uuidString)-\(Int(subscription.nextPaymentDate.timeIntervalSince1970 / 86_400))"
        GhafEventNotifications.prepareScheduledEvent(key: eventKey, title: content.title, message: content.body,
                                                    itemID: subscription.id.uuidString, date: reminderDate)
        content.userInfo = ["inboxTarget": subscription.id.uuidString, "eventKey": eventKey,
                            "eventKind": GhafInboxEventKind.subscriptionDue.rawValue,
                            "subscriptionID": subscription.id.uuidString]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    static func cancel(_ subscription: GhafSubscription) {
        cancel(id: subscription.id)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ghaf.subscription.\(id.uuidString)"])
        GhafEventNotifications.removeFutureSubscriptionEvent(id: id)
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("ghaf.subscription.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        GhafEventNotifications.removeFutureSubscriptionEvents()
    }
}
