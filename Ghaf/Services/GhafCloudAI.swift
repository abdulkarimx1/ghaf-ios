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
    static let endpoint = URL(string: "https://ghaf-ai.ghafapp.workers.dev/chat")!

    enum Failure: Error { case dailyLimit, unavailable }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    /// Set while Ghaf AI's voice mode is open: replies come back short and conversational.
    @MainActor static var conversational = false

    static func voiceUsage() async -> GhafVoiceUsage? {
        guard let url = URL(string: "/voice-usage", relativeTo: endpoint.deletingLastPathComponent()) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        request.setValue(GhafAITier.current, forHTTPHeaderField: "X-Ghaf-Tier")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(GhafVoiceUsage.self, from: data)
    }

    static func reserveVoiceTurn(languageCode: String) async -> (usage: GhafVoiceUsage, allowed: Bool)? {
        guard let url = URL(string: "/voice-turn", relativeTo: endpoint.deletingLastPathComponent()) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tier": GhafAITier.current, "language": languageCode])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode,
              let usage = try? JSONDecoder().decode(GhafVoiceUsage.self, from: data) else { return nil }
        return (usage, status == 200)
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
        guard let url = URL(string: "/health", relativeTo: endpoint.deletingLastPathComponent()) else { return }
        _ = try? await URLSession.shared.data(from: url)
    }

    static func reply(question: String, facts: String, direct: String?, history: [(isUser: Bool, text: String)],
                      languageCode: String) async throws -> String {
        var request = URLRequest(url: endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Ghaf-Device")
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
        if let tier { UserDefaults.standard.set(tier, forKey: "ghaf.pro.activeTier") }
        else { UserDefaults.standard.removeObject(forKey: "ghaf.pro.activeTier") }
        return tier
    }

    static var current: String {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ghaf.pro.testUnlocked") {
            return UserDefaults.standard.string(forKey: "ghaf.pro.testTier") == "pro_monthly" ? "pro_monthly" : "pro_yearly"
        }
        if ProcessInfo.processInfo.arguments.contains("-GhafAIProTestAccess") { return "pro_monthly" }
        #endif
        return UserDefaults.standard.string(forKey: "ghaf.pro.activeTier") ?? "free"
    }
}
