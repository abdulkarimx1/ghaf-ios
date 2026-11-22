import Foundation
import SwiftData

struct GhafAccountMapping: Codable, Equatable {
    var bank: String
    var accountRef: String?
    var accountID: UUID
    var confirmations: Int
    var lastConfirmedAt: Date
}

struct GhafPendingAccountReference: Codable, Equatable {
    var transactionID: UUID
    var bank: String
    var accountRef: String?
}

@MainActor
enum GhafAccountMappings {
    private static let key = "ghaf.accountMappings.v1"

    private struct Store: Codable {
        var mappings: [GhafAccountMapping] = []
        var pending: [GhafPendingAccountReference] = []
    }

    private static var cachedStore: Store?
    private static var store: Store {
        get {
            if let cachedStore { return cachedStore }
            let value = (try? JSONDecoder().decode(Store.self, from: UserDefaults.standard.data(forKey: key) ?? Data())) ?? Store()
            cachedStore = value
            return value
        }
        set { cachedStore = newValue; UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func accountID(bank: String?, sender: String?, accountRef: String?) -> UUID? {
        exactAccountID(bank: bank, sender: sender, accountRef: accountRef) ?? (accountRef == nil ? bankOnlyAccountID(bank: bank, sender: sender) : nil)
    }

    static func exactAccountID(bank: String?, sender: String?, accountRef: String?) -> UUID? {
        let source = normalize(bank ?? sender ?? "")
        guard !source.isEmpty, let accountRef else { return nil }
        let records = store.mappings.filter { normalize($0.bank) == source }
        let ref = String(accountRef.filter(\.isNumber).suffix(4))
        let exact = Set(records.filter { $0.accountRef == ref }.map(\.accountID))
        return exact.count == 1 ? exact.first : nil
    }

    static func bankOnlyAccountID(bank: String?, sender: String?) -> UUID? {
        let source = normalize(bank ?? sender ?? "")
        guard !source.isEmpty else { return nil }
        let records = store.mappings.filter { normalize($0.bank) == source }
        let bankOnly = Set(records.map(\.accountID))
        return bankOnly.count == 1 ? bankOnly.first : nil
    }

    static func hasConflictingReference(bank: String?, sender: String?, accountRef: String?) -> Bool {
        guard let accountRef else { return false }
        let source = normalize(bank ?? sender ?? "")
        let ref = String(accountRef.filter(\.isNumber).suffix(4))
        return Set(store.mappings.filter { normalize($0.bank) == source && $0.accountRef == ref }.map(\.accountID)).count > 1
    }

    static func recordAlert(transactionID: UUID, bank: String?, sender: String?, accountRef: String?) {
        guard let source = sourceKey(bank: bank, sender: sender) else { return }
        var current = store
        current.pending.removeAll { $0.transactionID == transactionID }
        current.pending.append(.init(transactionID: transactionID, bank: source, accountRef: normalizedRef(accountRef)))
        current.pending = Array(current.pending.suffix(2_000))
        store = current
    }

    static func confirm(transactionID: UUID, bank: String?, sender: String?, accountRef: String?, accountID: UUID) {
        var current = store
        let evidence = current.pending.first { $0.transactionID == transactionID }
        guard let source = sourceKey(bank: bank ?? evidence?.bank, sender: sender) else { return }
        let ref = normalizedRef(accountRef ?? evidence?.accountRef)
        if let i = current.mappings.firstIndex(where: { normalize($0.bank) == normalize(source) && $0.accountRef == ref && $0.accountID == accountID }) {
            current.mappings[i].confirmations += 1
            current.mappings[i].lastConfirmedAt = .now
        } else {
            current.mappings.append(.init(bank: source, accountRef: ref, accountID: accountID, confirmations: 1, lastConfirmedAt: .now))
        }
        current.pending.removeAll { $0.transactionID == transactionID }
        store = current
    }

    /// Assigns matching pending records; review status is retained for any other unresolved issue.
    @discardableResult
    static func apply(bank: String, accountRef: String?, accountID: UUID, context: ModelContext) throws -> Int {
        let source = normalize(bank), ref = normalizedRef(accountRef)
        var current = store
        var changed = 0
        for evidence in current.pending where normalize(evidence.bank) == source && evidence.accountRef == ref {
            guard let transaction = try context.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == evidence.transactionID })).first,
                  transaction.needsReview, transaction.accountID != accountID else { continue }
            transaction.accountID = accountID
            changed += 1
        }
        try context.save()
        current.pending.removeAll { normalize($0.bank) == source && $0.accountRef == ref }
        store = current
        return changed
    }

    static func backupData() -> Data? { try? JSONEncoder().encode(store) }
    static func isValidBackup(_ data: Data?) -> Bool {
        guard let data else { return true }
        return (try? JSONDecoder().decode(Store.self, from: data)) != nil
    }
    static func restore(from data: Data?) {
        guard let data, let decoded = try? JSONDecoder().decode(Store.self, from: data) else { store = Store(); return }
        store = decoded
    }

    private static func sourceKey(bank: String?, sender: String?) -> String? {
        let value = bank ?? sender ?? ""
        return normalize(value).isEmpty ? nil : value
    }
    private static func normalizedRef(_ ref: String?) -> String? {
        guard let ref else { return nil }
        let value = String(ref.filter(\.isNumber).suffix(4))
        return value.isEmpty ? nil : value
    }
    private static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }
}
