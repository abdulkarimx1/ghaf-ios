import Foundation
import Security
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
    /// Today's spending per category, largest first (optional so older saved snapshots still decode).
    var todayCategories: [CategorySpend]? = nil
    /// Spending for each of the last seven days, oldest first, today last.
    var lastSevenDays: [Decimal]? = nil
    /// The city theme's bright accent and glow (0xRRGGBB, dark palette), so widgets match the app.
    var accent: UInt32? = nil
    var glow: UInt32? = nil
    /// Share of today's budget spent (BudgetCalculator's daily mode), unclamped; nil when no daily budget is set.
    var dailyBudgetUsed: Double? = nil

    struct CategorySpend: Codable, Equatable {
        let name: String
        let amount: Decimal
        var symbol: String? = nil
    }

    // 1.20 additions, all optional so snapshots written by older builds still decode.

    /// One calendar period (today, this week, this month) as the ledger saw it when the app wrote the snapshot.
    struct Period: Codable, Equatable {
        /// When the period ends; after this the widget knows the numbers belong to a past period.
        var end: Date
        var spent: Decimal
        /// The whole previous period of the same kind, for "vs last week".
        var previous: Decimal
        var count: Int
        /// Spending per slice (3-hour blocks for a day, days for a week, 7-day blocks for a month).
        var bars: [Decimal]
        var categories: [CategorySpend]
    }
    var day: Period? = nil
    var week: Period? = nil
    var month: Period? = nil

    /// The transaction Ghaf recorded most recently (by when it was logged, not its date).
    struct Recent: Codable, Equatable {
        var merchant: String?
        var category: String
        var symbol: String
        var amount: Decimal
        var currency: String
        var date: Date
        var isCredit: Bool
        var account: String?
        /// The bank whose message it came from; nil when entered by hand.
        var bank: String?
        var needsReview: Bool
    }
    var recent: Recent? = nil

    /// The budget the app's Budget screen uses: today's in daily mode, the month's (or salary cycle's) in category mode.
    struct Budget: Codable, Equatable {
        var limit: Decimal
        var spent: Decimal
        var title: String
        var end: Date
    }
    var budget: Budget? = nil

    /// Active subscriptions by next payment date. Amounts keep their own currency.
    struct Bill: Codable, Equatable {
        var name: String
        var amount: Decimal
        var currency: String
        var date: Date
        var symbol: String
    }
    var upcoming: [Bill]? = nil

    /// The App Group to use. Sideload tools re-sign with their own profile and often rename the group
    /// (AltStore lists the new names under `ALTAppGroups`; others only put them in the embedded profile),
    /// so every group the install actually grants is tried, Ghaf-named ones first.
    static let groupID: String = {
        let fallback = "group.com.ghaf.app"
        // In the widget, Bundle.main is the extension; its app is two folders up (Ghaf.app/PlugIns/x.appex).
        let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        let listed = [Bundle.main, app].compactMap { $0?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] }.flatMap { $0 }
        // The widget's own bundle often has no profile listing the renamed group, so read the app's too.
        let granted = ([Bundle.main, app].compactMap { $0 }.flatMap { GhafSigningProfile.load(from: $0).appGroups })
            .sorted { $0.lowercased().contains("ghaf") && !$1.lowercased().contains("ghaf") }
        return (listed + [fallback] + granted).first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? fallback
    }()
    private static let key = "ghaf.widget.snapshot"

    /// True when the signer kept the App Group, so app and widget see the same container.
    static var hasSharedContainer: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    /// Reads the App Group first, then the shared keychain, keeping the newer of the two.
    static func load() -> GhafWidgetSnapshot? {
        let decode = { (data: Data?) in data.flatMap { try? JSONDecoder().decode(GhafWidgetSnapshot.self, from: $0) } }
        let fromGroup = hasSharedContainer ? decode(UserDefaults(suiteName: groupID)?.data(forKey: key)) : nil
        let fromKeychain = decode(GhafWidgetKeychain.read())
        return [fromGroup, fromKeychain].compactMap { $0 }.max { $0.updated < $1.updated }
    }

    /// Writes to every channel that works on this install and returns which ones did.
    @discardableResult
    func save() -> (group: Bool, keychain: Bool) {
        guard let data = try? JSONEncoder().encode(self) else { return (false, false) }
        var group = false
        if Self.hasSharedContainer, let defaults = UserDefaults(suiteName: Self.groupID) {
            defaults.set(data, forKey: Self.key)
            group = true
        }
        return (group, GhafWidgetKeychain.write(data))
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

/// Second channel for installs whose signer drops the App Group (some sideload tools do): a keychain
/// item in "<team>.com.ghaf.shared". It only works when the signing profile allows that access group
/// (wildcard profiles do); otherwise both calls fail quietly and the widget asks the user to open Ghaf.
enum GhafWidgetKeychain {
    private static let service = "ghaf.widget.snapshot"

    /// The team prefix the signer gave this install, read from the default access group of a probe item.
    static let accessGroup: String? = {
        let probe: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "ghaf.widget.probe",
                                      kSecAttrAccount: "probe", kSecReturnAttributes: true]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(probe as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = probe
            add[kSecValueData] = Data()
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attributes = result as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let team = group.split(separator: ".").first, team.count == 10 else { return nil }
        // A wildcard profile ("TEAM.*") allows a shared name; otherwise only an explicitly granted group can be shared.
        let granted = GhafSigningProfile.current.keychainGroups
        if granted.isEmpty || granted.contains("\(team).*") { return "\(team).com.ghaf.shared" }
        return granted.first { $0.lowercased().contains("shared") || $0.lowercased().contains("group") } ?? "\(team).com.ghaf.shared"
    }()

    private static func query(_ group: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "snapshot", kSecAttrAccessGroup: group]
    }

    static func write(_ data: Data) -> Bool {
        guard let group = accessGroup else { return false }
        let base = query(group)
        if SecItemUpdate(base as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecSuccess { return true }
        var add = base
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> Data? {
        guard let group = accessGroup else { return nil }
        var q = query(group)
        q[kSecReturnData] = true
        var result: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
}

/// What the signing profile embedded by the installer grants this bundle. Read from `embedded.mobileprovision`
/// (a signed plist); empty when there is none, e.g. in the simulator or an App Store install.
struct GhafSigningProfile {
    var appGroups: [String] = []
    var keychainGroups: [String] = []
    var name: String?

    static let current = load(from: .main)

    static func load(from bundle: Bundle) -> GhafSigningProfile {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return .init() }
        return parse((try? Data(contentsOf: url)) ?? Data())
    }

    static func parse(_ data: Data) -> GhafSigningProfile {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound,
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return .init() }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return GhafSigningProfile(appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
                                  keychainGroups: entitlements["keychain-access-groups"] as? [String] ?? [],
                                  name: plist["Name"] as? String)
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
        /// When Ghaf recorded it, so a stale activity can say how long ago.
        var recordedAt: Date? = nil
        /// The user hides balances: show stars instead of the amount.
        var hidden: Bool? = nil
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
