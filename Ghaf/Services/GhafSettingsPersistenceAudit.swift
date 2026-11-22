import Foundation
import SwiftData

#if DEBUG
@MainActor
enum GhafSettingsPersistenceAudit {
    private static let keys = [
        GhafCalendar.weekStartKey, "ghaf.glass.enabled", "ghaf.glass.intensity", "ghaf.glass.grain", "ghaf.glass.glow", "ghaf.glass.tilt",
        "ghaf.ai.voiceCharacter", GhafWidgetSync.liveActivityEnabledKey, GhafWidgetSync.liveActivityBalanceKey,
        GhafWidgetSync.liveActivityDurationKey, GhafEventNotifications.transactionReviewKey,
        GhafEventNotifications.detectedSubscriptionKey, GhafEventNotifications.budgetThresholdKey,
        GhafEventNotifications.subscriptionDueKey, GhafDigestNotifications.morningKey,
        GhafDigestNotifications.eveningKey, GhafDigestNotifications.weeklyKey, GhafWidgetSync.liveActivityKey
    ]
    private static let snapshotKey = "ghaf.settingsAudit.originalDefaults"

    static func run(_ phase: String, context: ModelContext) throws -> String {
        switch phase {
        case "write":
            captureDefaults()
            let settings = try GhafPersistence.settings(in: context)
            settings.hasCompletedOnboarding = true
            settings.languageCode = "ar"
            settings.currency = "SAR"
            settings.themeName = "Dubai"
            settings.appearanceMode = "Light"
            settings.budgetMode = "Category"
            settings.showKeypadOnAdd = false
            settings.biometricLockEnabled = true
            settings.mapsAppPreference = "google"
            try context.save()
            let defaults = UserDefaults.standard
            defaults.set(2, forKey: GhafCalendar.weekStartKey)
            defaults.set(false, forKey: "ghaf.glass.enabled")
            defaults.set("subtle", forKey: "ghaf.glass.intensity")
            defaults.set(false, forKey: "ghaf.glass.grain")
            defaults.set(false, forKey: "ghaf.glass.glow")
            defaults.set(false, forKey: "ghaf.glass.tilt")
            defaults.set("Mariam", forKey: "ghaf.ai.voiceCharacter")
            defaults.set(false, forKey: GhafWidgetSync.liveActivityEnabledKey)
            defaults.set("hidden", forKey: GhafWidgetSync.liveActivityBalanceKey)
            defaults.set(60, forKey: GhafWidgetSync.liveActivityDurationKey)
            defaults.set(false, forKey: GhafWidgetSync.liveActivityKey)
            for key in [GhafEventNotifications.transactionReviewKey, GhafEventNotifications.detectedSubscriptionKey,
                        GhafEventNotifications.budgetThresholdKey, GhafEventNotifications.subscriptionDueKey,
                        GhafDigestNotifications.morningKey, GhafDigestNotifications.eveningKey, GhafDigestNotifications.weeklyKey] {
                defaults.set(false, forKey: key)
            }
            return "Settings persistence audit: values written. Terminate and relaunch to verify."
        case "assert":
            let settings = try GhafPersistence.settings(in: context)
            var failures: [String] = []
            if settings.languageCode != "ar" { failures.append("language") }
            if settings.currency != "SAR" { failures.append("currency") }
            if settings.themeName != "Dubai" { failures.append("theme") }
            if settings.appearanceMode != "Light" { failures.append("appearance") }
            if settings.showKeypadOnAdd { failures.append("keypad") }
            if settings.biometricLockEnabled != true { failures.append("biometric") }
            if UserDefaults.standard.integer(forKey: GhafCalendar.weekStartKey) != 2 { failures.append("week start") }
            if UserDefaults.standard.bool(forKey: "ghaf.glass.enabled") { failures.append("glass enabled") }
            if UserDefaults.standard.string(forKey: "ghaf.glass.intensity") != "subtle" { failures.append("glass intensity") }
            for key in ["ghaf.glass.grain", "ghaf.glass.glow", "ghaf.glass.tilt"] where UserDefaults.standard.bool(forKey: key) { failures.append(key) }
            if settings.mapsAppPreference != "google" { failures.append("maps app") }
            if UserDefaults.standard.string(forKey: "ghaf.ai.voiceCharacter") != "Mariam" { failures.append("voice") }
            if settings.budgetMode != "Category" { failures.append("budget mode") }
            if UserDefaults.standard.bool(forKey: GhafWidgetSync.liveActivityEnabledKey) { failures.append("Live Activity enabled") }
            if UserDefaults.standard.string(forKey: GhafWidgetSync.liveActivityBalanceKey) != "hidden" { failures.append("Live Activity balance") }
            if UserDefaults.standard.integer(forKey: GhafWidgetSync.liveActivityDurationKey) != 60 { failures.append("Live Activity duration") }
            for key in [GhafWidgetSync.liveActivityKey, GhafEventNotifications.transactionReviewKey,
                        GhafEventNotifications.detectedSubscriptionKey, GhafEventNotifications.budgetThresholdKey,
                        GhafEventNotifications.subscriptionDueKey, GhafDigestNotifications.morningKey,
                        GhafDigestNotifications.eveningKey, GhafDigestNotifications.weeklyKey]
            where UserDefaults.standard.bool(forKey: key) { failures.append(key) }
            restoreDefaults()
            guard failures.isEmpty else { throw NSError(domain: "GhafSettingsPersistenceAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: ", ")]) }
            return "Settings persistence audit passed: 26 values survived relaunch."
        default:
            throw NSError(domain: "GhafSettingsPersistenceAudit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown audit phase"])
        }
    }

    private static func captureDefaults() {
        let defaults = UserDefaults.standard
        let old = defaults.dictionaryRepresentation()
        let values = old.filter { keys.contains($0.key) }
        let missing = keys.filter { old[$0] == nil }
        if let data = try? JSONSerialization.data(withJSONObject: ["values": values, "missing": missing]) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    private static func restoreDefaults() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = snapshot["values"] as? [String: Any],
              let missing = snapshot["missing"] as? [String] else { return }
        for key in keys {
            if missing.contains(key) { defaults.removeObject(forKey: key) }
            else if let value = values[key] { defaults.set(value, forKey: key) }
        }
        defaults.removeObject(forKey: snapshotKey)
    }
}
#endif
