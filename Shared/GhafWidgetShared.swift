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

    static let groupID = "group.com.ghaf.app"
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
    }
    var arabic: Bool
}
#endif
