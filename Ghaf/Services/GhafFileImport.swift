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
            dictionaries = matrix.dropFirst().map { values in
                Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($0.element, $0.offset < values.count ? values[$0.offset] : "") })
            }
        } else if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            dictionaries = array
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["transactions"] as? [[String: Any]] {
            dictionaries = rows
        } else { throw GhafFileImportError.unsupported }

        let existingAccounts = try context.fetch(FetchDescriptor<GhafAccount>())
        var rows: [GhafFileImportRow] = [], skipped = 0
        for item in dictionaries {
            let fields = item.reduce(into: [String: Any]()) { $0[normalize($1.key)] = $1.value }
            let values = fields.sorted { $0.key < $1.key }
            guard let dateValue = value(fields, names: ["date", "transaction date", "تاريخ", "التاريخ"]) ?? values.compactMap({ parseDate(String(describing: $0.value)) == nil ? nil : String(describing: $0.value) }).first,
                  let date = parseDate(dateValue),
                  let amountValue = value(fields, names: ["amount", "value", "المبلغ", "القيمة"]) ?? values.compactMap({ decimal(String(describing: $0.value)) == nil ? nil : String(describing: $0.value) }).first,
                  let amount = decimal(amountValue), amount != 0,
                  let merchantValue = value(fields, names: ["merchant", "description", "payee", "name", "الوصف", "التاجر", "المتجر"]) ?? values.compactMap({ pair in
                      guard !["account", "wallet", "category", "currency", "type", "direction"].contains(where: pair.key.contains) else { return nil }
                      let text = String(describing: pair.value).trimmingCharacters(in: .whitespacesAndNewlines)
                      return text.count > 1 && decimal(text) == nil && parseDate(text) == nil ? text : nil
                  }).first,
                  !merchantValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { skipped += 1; continue }
            let account = value(fields, names: ["account", "wallet", "account name", "الحساب", "المحفظة"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = value(fields, names: ["category", "الفئة", "التصنيف"]) ?? "Other"
            let kind = value(fields, names: ["type", "direction", "transaction type", "النوع", "الاتجاه"])?.lowercased() ?? ""
            let isIncome = ["income", "credit", "deposit", "salary", "دخل", "إيداع", "ايداع"].contains(where: kind.contains)
                || ["income", "salary", "other income"].contains(where: category.lowercased().contains)
            rows.append(.init(date: date, amount: abs(amount), merchant: merchantValue.trimmingCharacters(in: .whitespacesAndNewlines),
                              category: category, direction: isIncome ? .credit : .debit,
                              account: account?.isEmpty == true ? nil : account,
                              currency: value(fields, names: ["currency", "عملة"])?.uppercased() ?? "AED"))
        }
        guard !rows.isEmpty else { throw GhafFileImportError.noTransactions }
        let names = Set(existingAccounts.map(\.name))
        return GhafFileImportPreview(rows: rows, skipped: skipped,
            accountsToCreate: Array(Set(rows.compactMap(\.account).filter { !names.contains($0) })).sorted())
    }

    static func commit(_ preview: GhafFileImportPreview, createAccounts: Bool, context: ModelContext) throws -> (imported: Int, duplicates: Int) {
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        var byName = Dictionary(accounts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var imported = 0, duplicates = 0, seen = Set<String>()
        do {
            if createAccounts {
                for name in preview.accountsToCreate where byName[name] == nil {
                    let account = GhafAccount(name: name, accountType: .cash, currency: "AED")
                    context.insert(account); byName[name] = account
                }
            }
            let existing = try context.fetch(FetchDescriptor<GhafTransaction>())
            for row in preview.rows {
                let accountID = row.account.flatMap { byName[$0]?.id }
                let merchant = row.merchant.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                let key = "\(row.date.timeIntervalSince1970)|\(NSDecimalNumber(decimal: row.amount).stringValue)|\(merchant)|\(accountID?.uuidString ?? "")"
                if existing.contains(where: { abs($0.date.timeIntervalSince(row.date)) < 1 && $0.amount == row.amount && $0.merchant?.localizedCaseInsensitiveCompare(row.merchant) == .orderedSame && $0.accountID == accountID }) || !seen.insert(key).inserted { duplicates += 1; continue }
                let parsed = ParsedTransaction(amount: row.amount, currency: row.currency, merchant: row.merchant, date: row.date, direction: row.direction, confidence: 1, bank: nil)
                context.insert(GhafTransaction(fingerprint: "file-\(UUID().uuidString)", parsed: parsed, category: row.category, needsReview: false, isReversal: false, accountID: accountID)); imported += 1
            }
            try context.save()
        } catch { context.rollback(); throw error }
        return (imported, duplicates)
    }

    private static func normalize(_ key: String) -> String { key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func value(_ row: [String: Any], names: [String]) -> String? {
        guard let pair = row.first(where: { key, _ in names.contains(where: { normalize(key) == normalize($0) || normalize(key).contains(normalize($0)) }) }) else { return nil }
        return String(describing: pair.value)
    }
    private static func decimal(_ value: String) -> Decimal? {
        var text = value.replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: "٬", with: ",")
        let digits = text.unicodeScalars.map { scalar in
            if let number = scalar.properties.numericValue, (0...9).contains(number), scalar.properties.generalCategory == .decimalNumber { return String(Int(number)) }
            return String(scalar)
        }.joined()
        text = String(digits.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" })
        if text.contains(","), text.contains(".") { text = text.replacingOccurrences(of: ",", with: "") }
        else { text = text.replacingOccurrences(of: ",", with: ".") }
        return Decimal(string: text)
    }
    private static func parseDate(_ value: String) -> Date? { DelimitedImport.date(value) }
}
