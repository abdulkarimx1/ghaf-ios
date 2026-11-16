import Foundation

/// Optional cloud replies through the user's own Ghaf AI Worker (backend/ghaf-ai-worker), which holds
/// the Gemini key. Off by default. Sends the question, totals-only facts and the ledger's answer;
/// never the transaction list. Any failure falls back to the on-device answer.
enum GhafCloudAI {
    static let enabledKey = "ghaf.ai.cloudEnabled"
    static let urlKey = "ghaf.ai.cloudURL"
    static let tokenKey = "ghaf.ai.cloudToken"   // Keychain

    static var endpoint: URL? {
        guard let text = UserDefaults.standard.string(forKey: urlKey)?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url.appendingPathComponent("chat")
    }

    static var isConfigured: Bool {
        UserDefaults.standard.bool(forKey: enabledKey) && endpoint != nil && Keychain.read(tokenKey)?.isEmpty == false
    }

    /// Facts without the per-transaction lines, so only totals leave the device.
    static func minimized(_ facts: String) -> String {
        facts.components(separatedBy: "\nLatest transactions:").first ?? facts
    }

    static func reply(question: String, facts: String, direct: String?, history: [(isUser: Bool, text: String)],
                      languageCode: String) async throws -> String {
        guard let endpoint, let token = Keychain.read(tokenKey) else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Ghaf-Token")
        let body: [String: Any] = [
            "question": question,
            "facts": minimized(facts),
            "direct": direct ?? "",
            "language": languageCode,
            "history": history.suffix(6).map { ["isUser": $0.isUser, "text": $0.text] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty
        else { throw URLError(.badServerResponse) }
        return reply
    }
}
