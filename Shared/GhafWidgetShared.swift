import Foundation
import Security
import WidgetKit
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
    var glass: Bool? = nil

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
    static var groupIDs: [String] {
        let groups = GhafSigningProfile.current.appGroups
        let listed = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return Array(Set(groups.isEmpty ? listed + ["group.com.ghaf.app"] : groups + listed))
            .filter { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }
    static var groupID: String { groupIDs.first ?? "group.com.ghaf.app" }
    private static let key = "ghaf.widget.snapshot"

    struct Heartbeat: Codable {
        let date: Date
        let family: String
        let kind: String
        let loadedFrom: String
        let groupID: String
        let hasSharedContainer: Bool
        let keychainGroup: String?
    }
    private static let heartbeatKey = "ghaf.widget.heartbeat"

    static func recordHeartbeat(family: String, kind: String, source: String) {
        let value = Heartbeat(date: .now, family: family, kind: kind,
                              loadedFrom: source,
                              groupID: groupID, hasSharedContainer: hasSharedContainer,
                              keychainGroup: GhafWidgetKeychain.accessGroup)
        guard let data = try? JSONEncoder().encode(value) else { return }
        for group in groupIDs { UserDefaults(suiteName: group)?.set(data, forKey: heartbeatKey) }
        _ = GhafWidgetKeychain.writeHeartbeat(data)
    }

    static var lastHeartbeat: Heartbeat? {
        let groupData = groupIDs.compactMap { UserDefaults(suiteName: $0)?.data(forKey: heartbeatKey) }
        let keychainData = GhafWidgetKeychain.readHeartbeat()
        return (groupData + [keychainData].compactMap { $0 }).compactMap { try? JSONDecoder().decode(Heartbeat.self, from: $0) }.max { $0.date < $1.date }
    }

    /// True when the signer kept the App Group, so app and widget see the same container.
    static var hasSharedContainer: Bool {
        !groupIDs.isEmpty
    }

    /// Reads the App Group first, then the shared keychain, keeping the newer of the two.
    static func load() -> GhafWidgetSnapshot? {
        loadWithSource().snapshot
    }

    static func loadWithSource() -> (snapshot: GhafWidgetSnapshot?, source: String) {
        let decode = { (data: Data?) in data.flatMap { try? JSONDecoder().decode(GhafWidgetSnapshot.self, from: $0) } }
        let fromGroup = groupIDs.compactMap { decode(UserDefaults(suiteName: $0)?.data(forKey: key)) }.max { $0.updated < $1.updated }
        let fromKeychain = decode(GhafWidgetKeychain.read())
        guard let newest = [fromGroup, fromKeychain].compactMap({ $0 }).max(by: { $0.updated < $1.updated }) else { return (nil, "none") }
        return (newest, fromKeychain.map { $0.updated > (fromGroup?.updated ?? .distantPast) } == true ? "keychain" : "group")
    }

    /// Writes to every channel that works on this install and returns which ones did.
    @discardableResult
    func save() -> (group: Bool, keychain: Bool) {
        guard let data = try? JSONEncoder().encode(self) else { return (false, false) }
        for group in Self.groupIDs { UserDefaults(suiteName: group)?.set(data, forKey: Self.key) }
        let group = !Self.groupIDs.isEmpty
        return (group, GhafWidgetKeychain.write(data))
    }

    /// "AED 1,234.50", or stars while the user hides balances.
    func money(_ value: Decimal, currency code: String? = nil) -> String {
        let code = code ?? currency
        guard !hidden else { return "\(code) ✦✦✦✦" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: arabic ? "ar_AE" : "en_AE")
        formatter.minimumFractionDigits = GhafCurrencyDigits.fractionDigits(for: code)
        formatter.maximumFractionDigits = GhafCurrencyDigits.fractionDigits(for: code)
        return "\(code) " + (formatter.string(from: value as NSDecimalNumber) ?? "\(value)")
    }
}

struct GhafMoneyTip: Codable, Identifiable {
    let id: Int
    let en: String
    let ar: String
    let source: String
    let url: String

    static let endpoint = URL(string: "https://ghaf-ai.ghafapp.workers.dev/tips")!
    private static let cacheKey = "ghaf.widget.money-tips"

    static var cached: [GhafMoneyTip] {
        GhafWidgetSnapshot.groupIDs.compactMap { UserDefaults(suiteName: $0)?.data(forKey: cacheKey) }
            .compactMap { try? JSONDecoder().decode([GhafMoneyTip].self, from: $0) }.first ?? []
    }

    @discardableResult
    static func refresh() async -> [GhafMoneyTip] {
        guard let (data, response) = try? await URLSession.shared.data(from: endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.tips.count == 30 else { return cached }
        if let cache = try? JSONEncoder().encode(payload.tips) {
            for group in GhafWidgetSnapshot.groupIDs { UserDefaults(suiteName: group)?.set(cache, forKey: cacheKey) }
        }
        return payload.tips
    }

    private struct Payload: Decodable { let tips: [GhafMoneyTip] }
    static var today: GhafMoneyTip? {
        let tips = cached
        guard !tips.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1
        return tips[(day - 1) % tips.count]
    }
}

/// Second channel for installs whose signer drops the App Group (some sideload tools do): a keychain
/// item in "<team>.com.ghaf.shared". It only works when the signing profile allows that access group
/// (wildcard profiles do); otherwise both calls fail quietly and the widget asks the user to open Ghaf.
enum GhafWidgetKeychain {
    private static let service = "ghaf.widget.snapshot"
    private static let heartbeatService = "ghaf.widget.heartbeat"

    /// The team prefix the signer gave this install, read from the default access group of a probe item.
    static var accessGroup: String? {
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
        let own = GhafSigningProfile.current.keychainGroups
        let app: Bundle? = Bundle.main.bundleURL.pathExtension == "appex"
            ? Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) : .main
        let widget: Bundle?
        if Bundle.main.bundleURL.pathExtension == "appex" { widget = Bundle.main }
        else if let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("GhafWidgets.appex") { widget = Bundle(url: url) }
        else { widget = nil }
        let appGroups = (app.map(GhafSigningProfile.load(from:))?.keychainGroups ?? own)
        let widgetGroups = widget.map(GhafSigningProfile.load(from:))?.keychainGroups ?? own
        let shared = GhafSigningProfile.sharedKeychainGroups(app: appGroups, widget: widgetGroups)
        if let value = shared.first(where: { !$0.hasSuffix(".*") }) { return value }
        if own.isEmpty || own.contains("\(team).*") { return "\(team).com.ghaf.shared" }
        return own.first { $0.lowercased().contains("shared") || $0.lowercased().contains("group") } ?? "\(team).com.ghaf.shared"
    }

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

    static func writeHeartbeat(_ data: Data) -> Bool {
        guard let group = accessGroup else { return false }
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: heartbeatService,
                                  kSecAttrAccount: "heartbeat", kSecAttrAccessGroup: group]
        if SecItemUpdate(q as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecSuccess { return true }
        var add = q
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func readHeartbeat() -> Data? {
        guard let group = accessGroup else { return nil }
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: heartbeatService,
                                  kSecAttrAccount: "heartbeat", kSecAttrAccessGroup: group, kSecReturnData: true]
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
    var teamID: String?
    var expiry: Date?
    var exists = false

    static let current = load(from: .main)

    static func load(from bundle: Bundle) -> GhafSigningProfile {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return .init() }
        var profile = parse((try? Data(contentsOf: url)) ?? Data())
        profile.exists = true
        return profile
    }

    static func parse(_ data: Data) -> GhafSigningProfile {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound,
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return .init() }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return GhafSigningProfile(appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
                                  keychainGroups: entitlements["keychain-access-groups"] as? [String] ?? [],
                                  name: plist["Name"] as? String,
                                  teamID: (plist["TeamIdentifier"] as? [String])?.first,
                                  expiry: plist["ExpirationDate"] as? Date, exists: true)
    }

    static func sharedKeychainGroups(app: [String], widget: [String]) -> [String] {
        let candidates = app.flatMap { a in widget.compactMap { w -> String? in
            if a == w { return a }
            if a.hasSuffix(".*"), w.hasPrefix(String(a.dropLast())) { return w }
            if w.hasSuffix(".*"), a.hasPrefix(String(w.dropLast())) { return a }
            if a.hasSuffix(".*"), w.hasSuffix(".*"), a == w { return "\(a.dropLast(1))com.ghaf.shared" }
            return nil
        }}
        return Array(Set(candidates)).sorted()
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
        /// Fixed lifetime for this transaction activity; optional to decode activities made by older builds.
        var expiresAt: Date? = nil
        /// The user hides balances: show stars instead of the amount.
        var hidden: Bool? = nil
        var transactionID: UUID? = nil
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
