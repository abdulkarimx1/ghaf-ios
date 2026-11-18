import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// What the widgets show, written by the app into the shared App Group. Numbers come from the ledger
/// in the main currency only; nothing here is computed by the widget itself.
struct GhafWidgetSnapshot: Codable, Equatable {
    struct LastPurchase: Codable, Equatable {
        let merchant: String
        let amount: Decimal
        let currency: String
        let date: Date
    }

    var currency: String
    var balance: Decimal?          // nil when accounts mix currencies with no main-currency total
    var spentToday: Decimal
    var spentThisMonth: Decimal
    var lastPurchase: LastPurchase?
    var hidden: Bool
    var arabic: Bool
    var updated: Date

    /// The App Group to use. Sideloaders such as AltStore and SideStore rename the group (adding the
    /// signing team) and list the real names under `ALTAppGroups` in Info.plist, so try those first.
    static let groupID: String = {
        let fallback = "group.com.ghaf.app"
        // In the widget, Bundle.main is the extension; its app is two folders up (Ghaf.app/PlugIns/x.appex).
        let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        let listed = [Bundle.main, app].compactMap { $0?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] }.flatMap { $0 }
        return (listed + [fallback]).first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? fallback
    }()
    private static let key = "ghaf.widget.snapshot"

    static func load() -> GhafWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GhafWidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.groupID), let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// "AED 1,234.50", or stars while the user hides balances.
    func money(_ value: Decimal, currency code: String? = nil) -> String {
        let code = code ?? currency
        guard !hidden else { return "\(code) ✦✦✦✦" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: arabic ? "ar_AE" : "en_AE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(code) " + (formatter.string(from: value as NSDecimalNumber) ?? "\(value)")
    }
}

#if canImport(ActivityKit)
/// A purchase Ghaf just recorded, shown on the Lock Screen and in the Dynamic Island.
struct GhafPurchaseAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var merchant: String
        var amount: Decimal
        var currency: String
        var isCredit: Bool
        var accountName: String?
        var balance: Decimal?
        var needsReview: Bool
        /// SF Symbol for the category, so the activity shows what kind of purchase it was.
        var symbol: String = "bag.fill"
        var category: String = ""
    }
    var arabic: Bool
    /// The user's theme colours (0xRRGGBB), so the activity looks like Ghaf.
    var accent: UInt32 = 0x1B6B66
    var glow: UInt32 = 0x6FD0CC
}
#endif

#if canImport(SwiftUI)
import SwiftUI
extension Color {
    init(ghafHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
#endif
