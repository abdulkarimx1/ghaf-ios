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
