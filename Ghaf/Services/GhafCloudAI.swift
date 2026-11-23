import Foundation
import Observation
import StoreKit

struct GhafVoiceUsage: Decodable, Equatable {
    let used: Int
    let limit: Int
    let resetsAt: Date

    init(used: Int, limit: Int, resetsAt: Date) {
        self.used = used
        self.limit = limit
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey { case used, limit, resetsAt }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        used = try values.decode(Int.self, forKey: .used)
        limit = try values.decode(Int.self, forKey: .limit)
        let raw = try values.decode(String.self, forKey: .resetsAt)
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: raw) ?? {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: raw)
        }()
        guard let date else { throw DecodingError.dataCorruptedError(forKey: .resetsAt, in: values, debugDescription: "Invalid reset date") }
        resetsAt = date
    }
}

enum GhafAIStage: Hashable {
    case listening, transcribing
    case checkingTransactions(count: Int, period: String)
    case addingPurchases(Int), askingAI, drawingChart, preparingDraft

    func label(languageCode: String) -> String {
        let ar = languageCode == "ar"
        switch self {
        case .listening: return ar ? "غاف يستمع…" : "Listening…"
        case .transcribing: return ar ? "يحوّل كلامك إلى نص" : "Turning your voice into text"
        case .checkingTransactions(let count, let period):
            return ar ? "يراجع \(count) عملية · \(period)" : "Checking \(count) transactions · \(period)"
        case .addingPurchases(let count): return ar ? "يحسب \(count) عملية شراء" : "Adding up \(count) purchases"
        case .askingAI: return ar ? "يسأل غاف AI" : "Asking Ghaf AI"
        case .drawingChart: return ar ? "يرسم مخططك" : "Drawing your chart"
        case .preparingDraft: return ar ? "يجهز مسودة لمراجعتها" : "Preparing a draft for you to confirm"
        }
    }
}

@MainActor @Observable
final class GhafAIProgress {
    static let shared = GhafAIProgress()
    var stage: GhafAIStage?
}

/// Optional cloud replies through Ghaf's own server (backend/ghaf-ai-worker), which holds the model
/// keys. Off until the user turns it on. Sends the question, totals-only facts and the ledger's answer,
/// never the transaction list, with a random per-install ID used only for the free daily limit.
/// Any failure falls back to the on-device answer.
enum GhafCloudAI {
    static let enabledKey = "ghaf.ai.cloudEnabled"
    private static let deviceKey = "ghaf.ai.deviceID"   // Keychain
    static let accessCodeKey = "ghaf.pro.accessCode"
    static let endpoint = URL(string: "https://ghaf-ai.ghafapp.workers.dev/chat")!

    #if DEBUG
    @MainActor static var fixtureNetworkIsDisabledForRequests: Bool { GhafScreenshotFixture.enabled }
    #else
    @MainActor static var fixtureNetworkIsDisabledForRequests: Bool { false }
    #endif

    static func setBuildHeader(on request: inout URLRequest) {
        #if targetEnvironment(simulator)
        request.setValue("simulator", forHTTPHeaderField: "X-Ghaf-Build")
        #elseif DEBUG
        request.setValue("debug", forHTTPHeaderField: "X-Ghaf-Build")
        #else
        request.setValue("release", forHTTPHeaderField: "X-Ghaf-Build")
        #endif
    }

    enum Failure: Error { case dailyLimit, unavailable }
    static let accessRevoked = Notification.Name("GhafProAccessCodeRevoked")

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    /// Set while Ghaf AI's voice mode is open: replies come back short and conversational.
    @MainActor static var conversational = false

    static func voiceUsage() async -> GhafVoiceUsage? {
        if await fixtureNetworkIsDisabledForRequests { return nil }
        guard let url = URL(string: "/voice-usage", relativeTo: endpoint.deletingLastPathComponent()) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        setBuildHeader(on: &request)
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        request.setValue(GhafAITier.current, forHTTPHeaderField: "X-Ghaf-Tier")
        if let code = Keychain.read(accessCodeKey) { request.setValue(code, forHTTPHeaderField: "X-Ghaf-Code") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 401, Keychain.read(accessCodeKey) != nil { GhafProAccess.removeAccessCode() }
        guard status == 200 else { return nil }
        return try? JSONDecoder().decode(GhafVoiceUsage.self, from: data)
    }

    static func reserveVoiceTurn(languageCode: String) async -> (usage: GhafVoiceUsage, allowed: Bool)? {
        if await fixtureNetworkIsDisabledForRequests { return nil }
        guard let url = URL(string: "/voice-turn", relativeTo: endpoint.deletingLastPathComponent()) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        setBuildHeader(on: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        if let code = Keychain.read(accessCodeKey) { request.setValue(code, forHTTPHeaderField: "X-Ghaf-Code") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tier": GhafAITier.current, "language": languageCode])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 401, Keychain.read(accessCodeKey) != nil { GhafProAccess.removeAccessCode() }
        guard let usage = try? JSONDecoder().decode(GhafVoiceUsage.self, from: data) else { return nil }
        return (usage, status == 200)
    }

    enum RedeemResult { case success, invalid, unavailable }

    static func redeemAccessCode(_ code: String) async -> RedeemResult {
        if await fixtureNetworkIsDisabledForRequests { return .unavailable }
        guard let url = URL(string: "/redeem", relativeTo: endpoint.deletingLastPathComponent()) else { return .unavailable }
        var request = URLRequest(url: url, timeoutInterval: 12)
        setBuildHeader(on: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .unavailable }
        if status == 200 { return .success }
        return status == 401 || status == 429 ? .invalid : .unavailable
    }

    /// What turning it on means, shown wherever it can be switched on.
    static func disclosure(ar: Bool) -> String {
        ar ? "يرسل خادم غاف سؤالك ورسائلك الأخيرة وملخص المجاميع والحسابات وأبرز التجار وذكرياتك المحفوظة إلى Gemini من Google أو Cloudflare AI للرد. لا تُرسل قائمة العمليات أو أرقام الحسابات."
           : "Ghaf routes your question, recent messages and a summary of totals, accounts, top merchants and saved memories through its server to Google Gemini or Cloudflare AI. Your transaction list and account numbers aren't sent."
    }

    static func liveDisclosure(ar: Bool) -> String {
        ar ? "في المحادثة الصوتية، يُرسل صوتك مباشرةً إلى Google للتحدث مع غاف."
           : "In voice chat, your voice is streamed to Google so Ghaf can talk with you."
    }

    /// Random, not tied to the user or the device hardware; survives reinstall so the daily limit holds.
    static var deviceID: String {
        if let existing = Keychain.read(deviceKey) { return existing }
        let id = UUID().uuidString
        Keychain.save(id, for: deviceKey)
        return id
    }

    /// Facts without the per-transaction lines, so only totals leave the device.
    static func minimized(_ facts: String) -> String {
        facts.components(separatedBy: "\nLatest transactions:").first ?? facts
    }

    static func prewarm() async {
        if await fixtureNetworkIsDisabledForRequests { return }
        guard let url = URL(string: "/health", relativeTo: endpoint.deletingLastPathComponent()) else { return }
        var request = URLRequest(url: url)
        setBuildHeader(on: &request)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func reply(question: String, facts: String, direct: String?, history: [(isUser: Bool, text: String)],
                      languageCode: String) async throws -> String {
        if await fixtureNetworkIsDisabledForRequests { throw Failure.unavailable }
        var request = URLRequest(url: endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        setBuildHeader(on: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        if let code = Keychain.read(accessCodeKey) { request.setValue(code, forHTTPHeaderField: "X-Ghaf-Code") }
        let body: [String: Any] = [
            "question": question,
            "facts": minimized(facts),
            "direct": direct ?? "",
            "language": languageCode,
            "tier": GhafAITier.current,
            "history": history.suffix(6).map { ["isUser": $0.isUser, "text": $0.text] },
            "mode": await conversational ? "voice" : "chat"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        await MainActor.run { GhafAIProgress.shared.stage = .askingAI }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw Failure.dailyLimit }
        if status == 401, Keychain.read(accessCodeKey) != nil { GhafProAccess.removeAccessCode() }
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty
        else { throw Failure.unavailable }
        return reply
    }
}

enum GhafAITier {
    /// Refreshes the local tier from verified StoreKit entitlements. The Worker currently
    /// receives only the resulting tier string and must treat it as client-claimed.
    @MainActor static func refreshVerifiedEntitlement() async -> String? {
        var tier: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }
            if transaction.productID == "com.ghaf.app.pro.monthly" { tier = "pro_monthly" }
            if transaction.productID == "com.ghaf.app.pro.yearly" { tier = "pro_yearly" }
        }
        GhafProAccess.storeVerifiedStoreKitTier(tier)
        return GhafProAccess.currentTier
    }

    static var current: String {
        GhafProAccess.currentTier
    }
}

/// Single cached Pro decision shared by Ghaf AI, Settings, and widget synchronization.
enum GhafProAccess {
    private static let storeKitTierKey = "ghaf.pro.activeTier"
    private static let debugUnlockKey = "ghaf.pro.testUnlocked"

    static var currentTier: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GhafAINonProTestAccess") { return "free" }
        if UserDefaults.standard.bool(forKey: debugUnlockKey) || ProcessInfo.processInfo.arguments.contains("-GhafAIProTestAccess") {
            return UserDefaults.standard.string(forKey: "ghaf.pro.testTier") == "pro_monthly" ? "pro_monthly" : "pro_yearly"
        }
        #endif
        if Keychain.read(GhafCloudAI.accessCodeKey) != nil { return "pro_yearly" }
        return UserDefaults.standard.string(forKey: storeKitTierKey) ?? "free"
    }

    static var hasAccess: Bool { currentTier != "free" }
    static var hasAccessCode: Bool { Keychain.read(GhafCloudAI.accessCodeKey) != nil }
    static var isKnown: Bool {
        let cached = hasAccessCode || UserDefaults.standard.bool(forKey: "ghaf.pro.entitlementKnown")
            || UserDefaults.standard.string(forKey: storeKitTierKey) != nil
        #if DEBUG
        return cached || UserDefaults.standard.bool(forKey: debugUnlockKey)
            || ProcessInfo.processInfo.arguments.contains("-GhafAIProTestAccess")
            || ProcessInfo.processInfo.arguments.contains("-GhafAINonProTestAccess")
        #else
        return cached
        #endif
    }

    static func storeVerifiedStoreKitTier(_ tier: String?) {
        if let tier { UserDefaults.standard.set(tier, forKey: storeKitTierKey) }
        else { UserDefaults.standard.removeObject(forKey: storeKitTierKey) }
        UserDefaults.standard.set(true, forKey: "ghaf.pro.entitlementKnown")
        syncWidgetFlag()
    }

    static func saveAccessCode(_ code: String) {
        Keychain.save(code, for: GhafCloudAI.accessCodeKey)
        syncWidgetFlag()
    }

    static func removeAccessCode() {
        Keychain.delete(GhafCloudAI.accessCodeKey)
        syncWidgetFlag()
        NotificationCenter.default.post(name: GhafCloudAI.accessRevoked, object: nil)
    }

    static func syncWidgetFlag() {
        let unlocked = hasAccess
        for group in GhafWidgetSnapshot.groupIDs {
            UserDefaults(suiteName: group)?.set(unlocked, forKey: GhafWidgetProAccess.key)
        }
    }
}
