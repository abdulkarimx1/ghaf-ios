import Foundation
import SwiftData
import UserNotifications
import Security
import WidgetKit
import ActivityKit

@MainActor
enum GhafResetService {
    static func run(context: ModelContext) async throws -> [String] {
        let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
        let subscriptions = try context.fetch(FetchDescriptor<GhafSubscription>())
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        let settings = try context.fetch(FetchDescriptor<GhafSettings>())
        let rules = try context.fetch(FetchDescriptor<MerchantCategoryRule>())
        let memories = try context.fetch(FetchDescriptor<GhafMemory>())
        let chats = try context.fetch(FetchDescriptor<GhafChat>())
        transactions.forEach(context.delete)
        subscriptions.forEach(context.delete)
        accounts.forEach(context.delete)
        rules.forEach(context.delete)
        memories.forEach(context.delete)
        chats.forEach(context.delete)
        settings.forEach(context.delete)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        #if DEBUG
        let remaining = try [
            "transactions=\(context.fetchCount(FetchDescriptor<GhafTransaction>()))",
            "subscriptions=\(context.fetchCount(FetchDescriptor<GhafSubscription>()))",
            "accounts=\(context.fetchCount(FetchDescriptor<GhafAccount>()))",
            "settings=\(context.fetchCount(FetchDescriptor<GhafSettings>()))",
            "rules=\(context.fetchCount(FetchDescriptor<MerchantCategoryRule>()))",
            "memories=\(context.fetchCount(FetchDescriptor<GhafMemory>()))",
            "chats=\(context.fetchCount(FetchDescriptor<GhafChat>()))"
        ]
        print("Ghaf reset model counts: \(remaining.joined(separator: ", "))")
        #endif

        var issues: [String] = []
        await removeNotifications()
        await GhafWidgetSync.endAll()

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // In-memory learned state would otherwise be written straight back on the next save (R8).
        GhafAccountMappings.forgetCachedStore()
        MerchantCategorizer.invalidateLearner()
        for group in GhafWidgetSnapshot.groupIDs {
            UserDefaults(suiteName: group)?.removePersistentDomain(forName: group)
        }
        for group in GhafSigningProfile.current.appGroups where !GhafWidgetSnapshot.groupIDs.contains(group) {
            UserDefaults(suiteName: group)?.removePersistentDomain(forName: group)
        }

        URLCache.shared.removeAllCachedResponses()
        let files = FileManager.default
        if let cacheURL = files.urls(for: .cachesDirectory, in: .userDomainMask).first {
            do {
                for url in try files.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) where url.lastPathComponent.hasPrefix("Ghaf") {
                    try files.removeItem(at: url)
                }
            }
            catch { issues.append("Caches: \(error.localizedDescription)") }
        }
        if let supportURL = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let photo = supportURL.appendingPathComponent("profile-photo.jpg")
            if files.fileExists(atPath: photo.path) { do { try files.removeItem(at: photo) } catch { issues.append("Profile photo: \(error.localizedDescription)") } }
        }
        if let temporary = try? files.contentsOfDirectory(at: files.temporaryDirectory, includingPropertiesForKeys: nil) {
            for url in temporary where url.lastPathComponent.hasPrefix("Ghaf") {
                do { try files.removeItem(at: url) } catch { issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        deleteKeychainItems(&issues)
        WidgetCenter.shared.reloadAllTimelines()
        return issues
    }

    private static func removeNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("ghaf.") })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix("ghaf.") })
    }

    private static func deleteKeychainItems(_ issues: inout [String]) {
        let groups = Set(GhafSigningProfile.current.keychainGroups + (GhafWidgetKeychain.accessGroup.map { [$0] } ?? []))
        let accounts = ["ghaf.ai.deviceID", "ghaf.drive.refresh"]
        for account in accounts {
            var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound { issues.append("keychain:\(account)") }
            for group in groups {
                query[kSecAttrAccessGroup] = group
                let scopedStatus = SecItemDelete(query as CFDictionary)
                if scopedStatus != errSecSuccess && scopedStatus != errSecItemNotFound { issues.append("keychain:\(group)") }
            }
        }
        let services = ["ghaf.widget.snapshot", "ghaf.widget.heartbeat", "ghaf.widget.probe"]
        for service in services {
            var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound { issues.append("keychain:\(service)") }
            for group in groups {
                query[kSecAttrAccessGroup] = group
                let scopedStatus = SecItemDelete(query as CFDictionary)
                if scopedStatus != errSecSuccess && scopedStatus != errSecItemNotFound { issues.append("keychain:\(group)") }
            }
        }
    }
}
