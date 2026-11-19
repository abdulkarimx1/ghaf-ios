import Foundation
import UIKit

@MainActor
enum GhafBankAppDetector {
    static func installedBanks() -> [GhafBankSupportContact] {
        GhafBankSupportDirectory.contacts.filter { bank in
            guard let scheme = bank.urlScheme,
                  let url = URL(string: "\(scheme)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }
}

enum GhafAutomationBanks {
    static let key = "ghaf.automation.banks"

    static func selected(using detected: [GhafBankSupportContact], defaults: UserDefaults = .standard) -> [String] {
        guard defaults.object(forKey: key) != nil else {
            let names = detected.map(\.name)
            defaults.set(names, forKey: key)
            return names
        }
        return defaults.stringArray(forKey: key) ?? []
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
