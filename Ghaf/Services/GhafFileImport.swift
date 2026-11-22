import Foundation
import SwiftData
import GhafCore

struct GhafFileImportRow: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Decimal
    let merchant: String
    let category: String
    let direction: TransactionDirection
    let account: String?
    let currency: String
    let needsReview: Bool
    let reference: String?
    let hasTime: Bool
}

struct GhafFileImportPreview {
    let rows: [GhafFileImportRow]
    let skipped: Int
    let accountsToCreate: [String]
}

enum GhafFileImportError: LocalizedError {
    case unsupported, noTransactions
    var errorDescription: String? {
        switch self {
        case .unsupported: "This file is not a supported CSV or transaction JSON file."
        case .noTransactions: "No rows with a valid date, amount and description were found."
        }
    }
}

@MainActor
enum GhafFileImport {
    static func preview(_ url: URL, context: ModelContext) throws -> GhafFileImportPreview {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let dictionaries: [[String: Any]]
        if ["csv", "tsv", "txt"].contains(url.pathExtension.lowercased()) {
            let raw = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{FEFF}", with: "")
            let matrix = try DelimitedImport.rows(raw)
            let headers = matrix[0]
            dictionaries = matrix.dropFirst().map { values in DelimitedImport.dictionary(headers: headers, values: values).mapValues { $0 as Any } }
        } else if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            dictionaries = array
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["transactions"] as? [[String: Any]] {
            dictionaries = rows
        } else { throw GhafFileImportError.unsupported }

        let existingAccounts = try context.fetch(FetchDescriptor<GhafAccount>())
        let defaultCurrency = try context.fetch(FetchDescriptor<GhafSettings>()).first?.currency ?? "AED"
        var rows: [GhafFileImportRow] = [], skipped = 0
        for item in dictionaries {
            let fields = item.reduce(into: [String: String]()) { $0[normalize($1.key)] = String(describing: $1.value) }
            let dateAliases = ["date", "transaction date", "date/time", "booking date", "posted date", "value date", "تاريخ", "التاريخ"]
            let amountAliases = ["amount", "transaction amount", "income amount", "credit amount", "deposit amount", "income", "value", "المبلغ", "القيمة"]
            let debitAliases = ["debit", "debit amount", "withdrawal", "withdrawals", "money out", "مدين", "السحب"]
            let creditAliases = ["credit", "credit amount", "deposit", "money in", "دائن", "إيداع", "ايداع"]
            let debitValue = value(fields, names: debitAliases).flatMap { $0.isEmpty ? nil : $0 }
            let creditValue = value(fields, names: creditAliases).flatMap { $0.isEmpty ? nil : $0 }
            let amountValue = value(fields, names: amountAliases)
            let hasSeparateAmount = debitValue != nil || creditValue != nil
            let separateDirection = DelimitedImport.direction(debit: debitValue, credit: creditValue)
            let rawAmount: Decimal?
            switch separateDirection {
            case .debit: rawAmount = debitValue.flatMap(decimal).map(abs)
            case .credit: rawAmount = creditValue.flatMap(decimal).map(abs)
            case nil: rawAmount = hasSeparateAmount ? nil : amountValue.flatMap(decimal)
            }
            let typeAliases = ["type", "direction", "transaction type", "transaction kind", "النوع", "الاتجاه"]
            let type = value(fields, names: typeAliases)
            let hasTypeColumn = item.keys.contains { typeAliases.contains(normalize($0)) }
            let amountHeader = item.keys.first { amountAliases.contains(normalize($0)) } ?? ""
            let categoryValue = value(fields, names: ["category", "transaction category", "الفئة", "التصنيف"]) ?? "Other"
            let classification = rawAmount.map { FileImportRules.classification(type: type, hasTypeColumn: hasTypeColumn, amount: $0, amountHeader: amountHeader, category: categoryValue) }
            guard let dateValue = value(fields, names: dateAliases),
                  let date = parseDate(dateValue),
                  let amount = rawAmount, amount != 0,
                  let direction = separateDirection ?? DelimitedImport.direction(amount: amountValue.flatMap(decimal)),
                  let merchantValue = value(fields, names: ["merchant", "description", "payee", "name", "details", "narrative", "الوصف", "التاجر", "المتجر"]),
                  !merchantValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { skipped += 1; continue }
            let account = value(fields, names: ["account", "wallet", "account name", "الحساب", "المحفظة"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = categoryValue
            let finalDirection = hasSeparateAmount ? direction : classification?.direction ?? direction
            let accountCurrency = account.flatMap { accountName in existingAccounts.first(where: { $0.name.caseInsensitiveCompare(accountName) == .orderedSame })?.currency }
            let currency = value(fields, names: ["currency", "عملة"])?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let reference = value(fields, names: ["reference", "reference number", "transaction id", "transaction reference", "ref", "رقم المرجع", "رقم العملية"])
            let hasTime = dateValue.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil || dateValue.contains("T")
            rows.append(.init(date: date, amount: abs(amount), merchant: merchantValue.trimmingCharacters(in: .whitespacesAndNewlines),
                              category: category, direction: finalDirection,
                              account: account?.isEmpty == true ? nil : account,
                              currency: currency.flatMap { $0.isEmpty ? nil : $0 } ?? accountCurrency ?? defaultCurrency,
                              needsReview: hasSeparateAmount ? false : classification?.needsReview ?? false,
                              reference: reference, hasTime: hasTime))
        }
        guard !rows.isEmpty else { throw GhafFileImportError.noTransactions }
        let names = Set(existingAccounts.map(\.name))
        return GhafFileImportPreview(rows: rows, skipped: skipped,
            accountsToCreate: Array(Set(rows.compactMap(\.account).filter { !names.contains($0) })).sorted())
    }

    static func commit(_ preview: GhafFileImportPreview, createAccounts: Bool, context: ModelContext) throws -> (imported: Int, duplicates: Int) {
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        var byName = Dictionary(accounts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var imported = 0, duplicates = 0, seen: [FileImportIdentity] = []
        do {
            if createAccounts {
                for name in preview.accountsToCreate where byName[name] == nil {
                    let currency = preview.rows.first(where: { $0.account == name })?.currency ?? "AED"
                    let account = GhafAccount(name: name, accountType: .cash, currency: currency)
                    context.insert(account); byName[name] = account
                }
            }
            let existing = try context.fetch(FetchDescriptor<GhafTransaction>())
            for row in preview.rows {
                let accountID = row.account.flatMap { byName[$0]?.id }
                let identity = FileImportIdentity(date: row.date, hasTime: row.hasTime, amount: row.amount, merchant: row.merchant, account: row.account, reference: row.reference)
                if existing.contains(where: { abs($0.date.timeIntervalSince(row.date)) < 1 && $0.amount == row.amount && $0.merchant?.localizedCaseInsensitiveCompare(row.merchant) == .orderedSame && $0.accountID == accountID }) || FileImportRules.isDuplicate(reference: row.reference, hasTime: row.hasTime, date: row.date, amount: row.amount, merchant: row.merchant, account: row.account, among: seen) { duplicates += 1; continue }
                seen.append(identity)
                let parsed = ParsedTransaction(amount: row.amount, currency: row.currency, merchant: row.merchant, date: row.date, direction: row.direction, confidence: 1, bank: nil)
                context.insert(GhafTransaction(fingerprint: "file-\(UUID().uuidString)", parsed: parsed, category: row.category, needsReview: row.needsReview, isReversal: false, accountID: accountID)); imported += 1
            }
            try context.save()
        } catch { context.rollback(); throw error }
        return (imported, duplicates)
    }

    private static func normalize(_ key: String) -> String { key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func value(_ row: [String: Any], names: [String]) -> String? {
        DelimitedImport.value(row.mapValues(String.init(describing:)), aliases: names)
    }
    private static func decimal(_ value: String) -> Decimal? { DelimitedImport.decimal(value) }
    private static func parseDate(_ value: String) -> Date? { DelimitedImport.date(value) }
}
