import Foundation
import UIKit

enum GhafAutomationBanks {
    static let key = "ghaf.automation.banks"

    /// Banks the user chose. iOS doesn't let Ghaf see which bank apps are installed, so nothing is preselected.
    static func selected(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func save(_ names: [String], defaults: UserDefaults = .standard) {
        defaults.set(names, forKey: key)
    }
}

enum GhafAutomationCapturePolicy {
#if DEBUG
    static func assertPolicy() {
        assert(shouldSkip(bankName: "Mashreq", chosenBanks: ["Mashreq"], captureEnabled: false))
        assert(!shouldSkip(bankName: "Unknown", chosenBanks: ["Mashreq"], captureEnabled: false))
        let defaults = UserDefaults(suiteName: "GhafAutomationCapturePolicy")!
        defaults.removePersistentDomain(forName: "GhafAutomationCapturePolicy")
        recordSkip(for: "Mashreq", defaults: defaults)
        assert(skippedCount(for: "Mashreq", defaults: defaults) == 1)
        defaults.removePersistentDomain(forName: "GhafAutomationCapturePolicy")
    }
#endif

    static func shouldSkip(bankName: String?, chosenBanks: [String], captureEnabled: Bool) -> Bool {
        guard let bankName, chosenBanks.contains(bankName) else { return false }
        return !captureEnabled
    }

    static func captureIsEnabled(for bankName: String, defaults: UserDefaults = .standard) -> Bool {
        let key = "ghaf.automation.bankEnabled.\(bankName)"
        return defaults.object(forKey: key) as? Bool ?? true
    }

    static func skippedCount(for bankName: String, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: "ghaf.automation.skipped.\(bankName)")
    }

    static func recordSkip(for bankName: String, defaults: UserDefaults = .standard) {
        let key = "ghaf.automation.skipped.\(bankName)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }
}
