import Foundation
import GhafCore

enum GhafMerchantAliasStore {
    private static let key = "ghaf.merchant.aliases"
    private static var cachedAliases: [String: String]?

    private static var aliases: [String: String] {
        if let cachedAliases { return cachedAliases }
        guard let data = UserDefaults.standard.data(forKey: key),
              let aliases = try? JSONDecoder().decode([String: String].self, from: data) else {
            cachedAliases = [:]
            return [:]
        }
        cachedAliases = aliases
        return aliases
    }

    static func displayName(_ raw: String?) -> String? {
        MerchantName.displayName(raw, aliases: aliases)
    }

    static func rename(_ raw: String, to alias: String) {
        var current = aliases
        current[MerchantName.key(raw)] = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: key); cachedAliases = current }
    }

    static func invalidateCache() { cachedAliases = nil }
}
