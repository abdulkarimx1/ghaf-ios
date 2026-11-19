import Foundation
import UserNotifications

enum GhafInboxEventKind: String, Codable {
    case transactionReview
    case detectedSubscription
    case budgetThreshold
    case subscriptionDue
}

struct GhafInboxEvent: Identifiable, Codable {
    let id: String
    let kind: GhafInboxEventKind
    let title: String
    let message: String
    let itemID: String?
    let date: Date
}

@MainActor
enum GhafEventNotifications {
    static let inboxUpdated = Notification.Name("GhafInboxUpdated")
    static let openInboxItem = Notification.Name("GhafOpenInboxItem")
    private static let eventsKey = "ghaf.inbox.events"
    private static let notifiedKeys = "ghaf.event.notifiedKeys"
    private static let pendingTargetKey = "ghaf.inbox.pendingTarget"
    private static let center = UNUserNotificationCenter.current()
    private static let delegate = InboxNotificationDelegate()

    static var events: [GhafInboxEvent] {
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let saved = (try? JSONDecoder().decode([GhafInboxEvent].self, from: UserDefaults.standard.data(forKey: eventsKey) ?? Data())) ?? []
        let recent = saved.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
        if recent.count != saved.count { save(recent) }
        return recent
    }

    static func configure() {
        center.delegate = delegate
    }

    static func consumePendingTarget() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: pendingTargetKey) }
        return UserDefaults.standard.string(forKey: pendingTargetKey)
    }

    static func record(
        key: String,
        kind: GhafInboxEventKind,
        title: String,
        message: String,
        itemID: String? = nil,
        notifies: Bool,
        delay: TimeInterval? = nil
    ) {
        var current = events
        guard !current.contains(where: { $0.id == key }) else { return }
        let event = GhafInboxEvent(id: key, kind: kind, title: title, message: message, itemID: itemID, date: .now)
        current.insert(event, at: 0)
        save(current)
        NotificationCenter.default.post(name: inboxUpdated, object: nil)

        var sent = Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? [])
        guard notifies, sent.insert(key).inserted else { return }
        UserDefaults.standard.set(Array(sent), forKey: notifiedKeys)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.userInfo = ["inboxTarget": itemID ?? key, "eventKey": key, "eventKind": kind.rawValue]
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
    }

    #if DEBUG
    static func scheduleDebugEvent() {
        record(key: "debug-inbox-event-\(UUID().uuidString)", kind: .transactionReview,
               title: "Check a transaction", message: "A transaction needs your review.",
               itemID: nil, notifies: true, delay: 5)
    }
    #endif

    private static func save(_ events: [GhafInboxEvent]) {
        if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: eventsKey) }
    }

    private final class InboxNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            let target = response.notification.request.content.userInfo["inboxTarget"] as? String
            UserDefaults.standard.set(target ?? "", forKey: pendingTargetKey)
            NotificationCenter.default.post(name: openInboxItem, object: target)
        }
    }
}
