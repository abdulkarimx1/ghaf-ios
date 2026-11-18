import Foundation

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

    /// What turning it on means, shown wherever it can be switched on.
    static func disclosure(ar: Bool) -> String {
        ar ? "إجابات أذكى عبر خادم غاف باستخدام Gemini من Google أو Gemma على Cloudflare. يُرسل سؤالك وملخص مجاميعك وإجابة سجلك فقط، وليس قائمة عملياتك أو أرقام حساباتك. لا تُحفظ أسئلتك؛ يُحفظ فقط عدد الأسئلة اليومي لمدة يومين. الخطة المجانية: ٢٠ سؤالاً يومياً، وبعدها يجيب غاف من جهازك."
           : "Smarter replies through Ghaf's server, using Google Gemini or Gemma on Cloudflare. Sends your question, a summary of your totals and the ledger's answer, never your transaction list or account numbers. Questions aren't stored; only a daily question count is kept, for two days. Free plan: 20 questions a day, then Ghaf answers on your iPhone."
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
            "history": history.suffix(6).map { ["isUser": $0.isUser, "text": $0.text] },
            "mode": await conversational ? "voice" : "chat"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
