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
    static let transactionReviewKey = "ghaf.notify.transactionReview"
    static let detectedSubscriptionKey = "ghaf.notify.detectedSubscription"
    static let budgetThresholdKey = "ghaf.notify.budgetThreshold"
    static let subscriptionDueKey = "ghaf.notify.subscriptionDue"
    static let inboxUpdated = Notification.Name("GhafInboxUpdated")
    static let openInboxItem = Notification.Name("GhafOpenInboxItem")
    private static let eventsKey = "ghaf.inbox.events"
    private static let notifiedKeys = "ghaf.event.notifiedKeys"
    private static let pendingTargetKey = "ghaf.inbox.pendingTarget"
    private static let center = UNUserNotificationCenter.current()
    private static let delegate = InboxNotificationDelegate()
#if DEBUG
    private static var fixtureEvents: [GhafInboxEvent]?
    private static var debugRequestKey: String { "ghaf.notify.debug" }
#endif

    static var events: [GhafInboxEvent] {
#if DEBUG
        if let fixtureEvents { return fixtureEvents }
#endif
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let saved = storedEvents
        let retained = saved.filter { $0.date >= cutoff }
        if retained.count != saved.count { save(retained) }
        return retained.filter { $0.date <= .now }.sorted { $0.date > $1.date }
    }

    static func configure() {
        center.delegate = delegate
    }

    static func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func prepareScheduledEvent(key: String, title: String, message: String, itemID: String, date: Date) {
        var current = storedEvents.filter { $0.date >= Date.now.addingTimeInterval(-30 * 24 * 60 * 60) }
        if let index = current.firstIndex(where: { $0.id == key }) {
            guard current[index].date > .now else { return }
            current[index] = GhafInboxEvent(id: key, kind: .subscriptionDue, title: title,
                                            message: message, itemID: itemID, date: date)
        } else {
            current.insert(GhafInboxEvent(id: key, kind: .subscriptionDue, title: title,
                                          message: message, itemID: itemID, date: date), at: 0)
        }
        save(current)
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
        store(key: key, kind: kind, title: title, message: message, itemID: itemID)
        guard notifies else { return }

        let sent = Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? [])
        guard !sent.contains(key) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.userInfo = ["inboxTarget": itemID ?? key, "eventKey": key, "eventKind": kind.rawValue]
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        Task { @MainActor in
            guard !Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? []).contains(key) else { return }
            do {
                try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
                var updated = Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? [])
                updated.insert(key)
                UserDefaults.standard.set(Array(updated), forKey: notifiedKeys)
            } catch {
                // A later event or settings change can retry; a failed request never consumes its key.
            }
        }
    }

    static func recordCaptureBanner(_ transaction: GhafTransaction, languageCode: String, unusual: Bool = false) {
        guard isEnabled(GhafDigestNotifications.autoTransactionKey) else { return }
        let ar = languageCode == "ar"
        let amount = GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: languageCode)
        let signed = transaction.direction == "credit" ? "+\(amount)" : "−\(amount)"
        let merchant = GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant)
            ?? GhafLocalization.category(transaction.category, languageCode: languageCode)
        let category = GhafLocalization.category(transaction.category, languageCode: languageCode)
        let content = UNMutableNotificationContent()
        content.title = ar ? "تم تسجيل العملية" : "Transaction saved"
        content.body = "\(signed) · \(merchant) · \(category)"
        if unusual { content.subtitle = ar ? "عملية أعلى من المعتاد" : "Higher than usual" }
        content.sound = .default
        content.userInfo = ["transactionID": transaction.id.uuidString]
        let key = "capture-result-\(transaction.id.uuidString)"
        let sent = Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? [])
        guard !sent.contains(key) else { return }
        Task { @MainActor in
            guard !Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? []).contains(key) else { return }
            do {
                try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
                var updated = Set(UserDefaults.standard.stringArray(forKey: notifiedKeys) ?? [])
                updated.insert(key)
                UserDefaults.standard.set(Array(updated), forKey: notifiedKeys)
            } catch { /* Keep the key retryable when notification delivery is unavailable. */ }
        }
    }

    static func removeFutureSubscriptionEvents() {
        save(storedEvents.filter { $0.kind != .subscriptionDue || $0.date <= .now })
        NotificationCenter.default.post(name: inboxUpdated, object: nil)
    }

    static func removeFutureSubscriptionEvent(id: UUID) {
        save(storedEvents.filter { $0.kind != .subscriptionDue || $0.itemID != id.uuidString || $0.date <= .now })
        NotificationCenter.default.post(name: inboxUpdated, object: nil)
    }

    private static func store(key: String, kind: GhafInboxEventKind, title: String, message: String, itemID: String?) {
        var current = events
        guard !current.contains(where: { $0.id == key }) else { return }
        let event = GhafInboxEvent(id: key, kind: kind, title: title, message: message, itemID: itemID, date: .now)
        current.insert(event, at: 0)
#if DEBUG
        if fixtureEvents != nil { fixtureEvents = current }
        else { save(current) }
#else
        save(current)
#endif
        NotificationCenter.default.post(name: inboxUpdated, object: nil)
    }

    #if DEBUG
    static func setFixtureEvents(_ events: [GhafInboxEvent]) {
        fixtureEvents = events
        NotificationCenter.default.post(name: inboxUpdated, object: nil)
    }

    static func scheduleDebugEvent(_ kind: String) {
        let localized: (String, String)
        switch kind {
        case "capture": localized = ("Transaction saved", "−AED 3.00 · Kookh Al Shay · Food")
        case "review": localized = ("Check a transaction", "A transaction needs your review.")
        case "subscription": localized = ("Payment coming up", "Netflix is due soon · 39.99 AED.")
        case "budget": localized = ("Food reached 80% of its budget", "Food spending reached 80% of its monthly budget.")
        case "salary": localized = ("Salary day", "Has your salary arrived? Open Ghaf to confirm it.")
        default: localized = ("Today in Ghaf", "You spent AED 23.00 across 2 transactions today.")
        }
        let content = UNMutableNotificationContent()
        content.title = localized.0
        content.body = localized.1
        content.sound = .default
        content.userInfo = ["debugKind": kind]
        Task { @MainActor in
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            try? await center.add(UNNotificationRequest(identifier: "ghaf.debug.\(kind).\(UUID().uuidString)", content: content,
                                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        }
    }
    #endif

    private static func save(_ events: [GhafInboxEvent]) {
        if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: eventsKey) }
    }

    private static var storedEvents: [GhafInboxEvent] {
        (try? JSONDecoder().decode([GhafInboxEvent].self, from: UserDefaults.standard.data(forKey: eventsKey) ?? Data())) ?? []
    }

    private final class InboxNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            await MainActor.run { NotificationCenter.default.post(name: GhafEventNotifications.inboxUpdated, object: nil) }
            return [.banner, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            let info = response.notification.request.content.userInfo
            let isSubscriptionDue = info["eventKind"] as? String == GhafInboxEventKind.subscriptionDue.rawValue
            let key = info["eventKey"] as? String
            let target = info["inboxTarget"] as? String
            let subscriptionID = info["subscriptionID"] as? String
            let title = response.notification.request.content.title
            let message = response.notification.request.content.body
            Task { @MainActor in
                if isSubscriptionDue, let key {
                    GhafEventNotifications.store(key: key, kind: .subscriptionDue, title: title,
                                                 message: message, itemID: subscriptionID)
                }
                UserDefaults.standard.set(target ?? "", forKey: GhafEventNotifications.pendingTargetKey)
                NotificationCenter.default.post(name: GhafEventNotifications.openInboxItem, object: target)
            }
        }
    }
}
