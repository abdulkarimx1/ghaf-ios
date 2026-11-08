import Foundation
import SwiftData
import GhafCore

struct GhafExternalImportResult {
    let accountsImported: Int
    let transactionsImported: Int
    let skippedTransactions: Int
    let recurringRulesNotImported: Int
    let sourceName: String
}

enum GhafExpendImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case noValidWallets
    case invalidTransactionData

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "The selected JSON file could not be read."
        case .unsupportedFormat: "This JSON file is not a supported Expend export."
        case .noValidWallets: "No valid wallets were found in the Expend export."
        case .invalidTransactionData: "The Expend transaction data is incomplete."
        }
    }
}

@MainActor
enum GhafExpendImportService {
    private static let categoryMap: [String: String] = [
        "food": "Dining",
        "games-and-entertainment": "Entertainment",
        "grocery": "Groceries",
        "health": "Health",
        "shopping": "Shopping",
        "subscriptions": "Subscriptions",
        "transportation": "Transport",
        "utilities": "Bills & Utilities",
        "others-income": "Transfers",
        "reimbursements": "Other",
        "salary": "Salary",
        "fcfb4ee5-fc91-4680-8265-588a4b84639a": "Other",
        "transfer": "Transfers",
        "transfer-fee": "Fees",
        "debt-repayment": "Debt Repayment",
        "payable-debt-expansion": "Borrowed Money",
        "payable-debt-interest": "Interest",
        "payment-collection": "Other",
        "receivable-debt-expansion": "Lent Money",
        "receivable-debt-interest": "Interest",
        "adjustment-expense": "Other",
        "adjustment-income": "Other"
    ]

    static func canImport(_ url: URL) -> Bool {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return root["wallets"] is [[String: Any]] && root["transactions"] is [[String: Any]]
    }

    static func importFile(from url: URL, context: ModelContext) throws -> GhafExternalImportResult {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GhafExpendImportError.unreadableFile
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let walletRows = root["wallets"] as? [[String: Any]],
              let transactionRows = root["transactions"] as? [[String: Any]] else {
            throw GhafExpendImportError.unsupportedFormat
        }

        let validWalletRows = walletRows.filter {
            string($0["_id"]) != nil && string($0["name"]) != nil
        }
        guard !validWalletRows.isEmpty else { throw GhafExpendImportError.noValidWallets }

        let walletIDs = Dictionary(uniqueKeysWithValues: validWalletRows.compactMap { row -> (String, UUID)? in
            guard let sourceID = string(row["_id"]) else { return nil }
            return (sourceID, UUID(uuidString: sourceID) ?? UUID())
        })

        let subcategoryNames: [String: String] = Dictionary(
            uniqueKeysWithValues: ((root["subcategories"] as? [[String: Any]]) ?? []).compactMap {
                guard let id = string($0["_id"]), let name = string($0["name"]) else { return nil }
                return (id, name)
            }
        )

        let walletsByID = Dictionary(
            uniqueKeysWithValues: validWalletRows.compactMap { row -> (String, [String: Any])? in
                guard let id = string(row["_id"]) else { return nil }
                return (id, row)
            }
        )

        let parsedTransactions = transactionRows.flatMap { row in
            prepare(row, walletIDs: walletIDs, walletsByID: walletsByID, subcategoryNames: subcategoryNames)
        }
        guard !parsedTransactions.isEmpty else {
            throw GhafExpendImportError.invalidTransactionData
        }

        // Parse and validate the complete file before touching existing records.
        let existingSettings = try context.fetch(FetchDescriptor<GhafSettings>()).first
        let profile = root["profile"] as? [String: Any] ?? [:]
        let mainCurrency = string(profile["mainCurrency"])?.uppercased() ?? "AED"
        let languageCode = string(profile["languageCode"]) == "ar" ? "ar" : (existingSettings?.languageCode ?? "en")

        let accounts: [GhafAccount] = validWalletRows.enumerated().map { index, row in
            let name = string(row["name"]) ?? (languageCode == "ar" ? "محفظة" : "Wallet")
            let sourceID = string(row["_id"]) ?? UUID().uuidString
            let accountID = walletIDs[sourceID] ?? UUID()
            let type = accountType(for: name)
            let currency = string(row["currencyCode"])?.uppercased() ?? mainCurrency
            let openingBalance = decimal(row["initialAmount"]) ?? 0
            let created = date(row["dateCreated"]) ?? .distantPast
            let institution = string(row["institution"])
            let archived = (row["isArchived"] as? Bool ?? false) || (row["deleted"] as? Bool ?? false)
            let primaryWalletID = string(profile["defaultWalletID"])
            let primary = primaryWalletID == sourceID || (primaryWalletID == nil && index == 0)
            return GhafAccount(
                id: accountID,
                name: name,
                institution: institution,
                accountType: type,
                currency: currency,
                openingBalance: openingBalance,
                openingDate: created,
                isArchived: archived,
                isPrimary: primary,
                sortOrder: integer(row["order"]) ?? index,
                notes: nil
            )
        }

        let categoryValues = Set(categoryMap.values).union(["Other"])
        let currentRules = try context.fetch(FetchDescriptor<MerchantCategoryRule>())
        let currentTransactions = try context.fetch(FetchDescriptor<GhafTransaction>())
        let currentAccounts = try context.fetch(FetchDescriptor<GhafAccount>())

        do {
            currentTransactions.forEach { context.delete($0) }
            currentAccounts.forEach { context.delete($0) }
            currentRules.forEach { context.delete($0) }

            let settings = existingSettings ?? GhafSettings()
            if existingSettings == nil { context.insert(settings) }
            settings.userName = string(profile["name"]) ?? settings.userName
            settings.currency = mainCurrency
            settings.languageCode = languageCode
            settings.categories = Array(categoryValues).sorted()
            settings.categoryBudgets = [:]
            settings.monthlyIncome = decimal(profile["monthlyIncome"]) ?? settings.monthlyIncome
            settings.fixedCommitments = decimal(profile["fixedCommitments"]) ?? settings.fixedCommitments
            settings.hasCompletedOnboarding = true
            settings.themeName = "Abu Dhabi"

            accounts.forEach { context.insert($0) }
            for item in parsedTransactions {
                let transaction = GhafTransaction(
                    fingerprint: item.fingerprint,
                    parsed: ParsedTransaction(
                        amount: item.amount,
                        currency: item.currency,
                        merchant: item.merchant,
                        date: item.date,
                        direction: item.direction,
                        confidence: 1,
                        bank: item.bank
                    ),
                    category: item.category,
                    needsReview: item.needsReview,
                    isReversal: item.isReversal,
                    accountID: item.accountID
                )
                transaction.note = item.note
                context.insert(transaction)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        let skipped = transactionRows.count - parsedTransactions.filter { !$0.isTransferMirror }.count
        return GhafExternalImportResult(
            accountsImported: accounts.count,
            transactionsImported: parsedTransactions.count,
            skippedTransactions: max(0, skipped),
            recurringRulesNotImported: (root["recurringTransactions"] as? [[String: Any]])?.count ?? 0,
            sourceName: "Expend"
        )
    }

    private struct PreparedTransaction {
        let fingerprint: String
        let amount: Decimal
        let currency: String
        let merchant: String?
        let date: Date
        let direction: TransactionDirection
        let category: String
        let note: String?
        let bank: String?
        let accountID: UUID?
        let needsReview: Bool
        let isReversal: Bool
        let isTransferMirror: Bool
    }

    private static func prepare(
        _ row: [String: Any],
        walletIDs: [String: UUID],
        walletsByID: [String: [String: Any]],
        subcategoryNames: [String: String]
    ) -> [PreparedTransaction] {
        guard let sourceID = string(row["_id"]),
              let type = string(row["type"])?.lowercased(),
              let amount = decimal(row["amount"]), amount > 0 else { return [] }
        if row["deleted"] as? Bool == true { return [] }

        let date = date(row["dateCreated"]) ?? date(row["lastUpdated"]) ?? .now
        let rawCategory = string(row["category"]) ?? "other"
        let category = categoryMap[rawCategory] ?? "Other"
        let subcategory = string(row["subcategory"]).flatMap { subcategoryNames[$0] }
        let merchant = string(row["name"])
        let sourceAccountID = string(row["srcWallet"]).flatMap { walletIDs[$0] }
        let sourceWallet = string(row["srcWallet"]).flatMap { walletsByID[$0] }
        let sourceCurrency = string(sourceWallet?["currencyCode"])?.uppercased() ?? "AED"
        let bank = string(sourceWallet?["institution"])
        let originalNotes = string(row["notes"])
        let noteParts = [originalNotes, subcategory.map { "Subcategory: \($0)" }]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let note = noteParts.isEmpty ? nil : noteParts.joined(separator: " · ")
        let reversal = (row["isReversal"] as? Bool ?? false) ||
            (string(row["name"])?.localizedCaseInsensitiveContains("refund") ?? false)

        if type == "transfer" {
            let source = PreparedTransaction(
                fingerprint: "expend-\(sourceID)-out",
                amount: amount,
                currency: sourceCurrency,
                merchant: merchant ?? "Transfer",
                date: date,
                direction: .debit,
                category: "Transfers",
                note: note,
                bank: bank,
                accountID: sourceAccountID,
                needsReview: sourceAccountID == nil,
                isReversal: false,
                isTransferMirror: false
            )
            guard let destinationID = string(row["destWallet"]),
                  let destinationAccountID = walletIDs[destinationID],
                  let destinationWallet = walletsByID[destinationID] else {
                return [source]
            }
            let destinationAmount = decimal(row["destAmount"]) ?? amount
            let destination = PreparedTransaction(
                fingerprint: "expend-\(sourceID)-in",
                amount: destinationAmount,
                currency: string(destinationWallet["currencyCode"])?.uppercased() ?? sourceCurrency,
                merchant: merchant ?? "Transfer",
                date: date,
                direction: .credit,
                category: "Transfers",
                note: note,
                bank: string(destinationWallet["institution"]),
                accountID: destinationAccountID,
                needsReview: false,
                isReversal: false,
                isTransferMirror: true
            )
            return [source, destination]
        }

        let direction: TransactionDirection = type == "income" ? .credit : .debit
        return [PreparedTransaction(
            fingerprint: "expend-\(sourceID)",
            amount: amount,
            currency: sourceCurrency,
            merchant: merchant,
            date: date,
            direction: direction,
            category: category,
            note: note,
            bank: bank,
            accountID: sourceAccountID,
            needsReview: sourceAccountID == nil,
            isReversal: reversal,
            isTransferMirror: false
        )]
    }

    private static func accountType(for name: String) -> GhafAccountType {
        let value = name.lowercased()
        if value.contains("cash") { return .cash }
        if value.contains("saving") { return .savings }
        if value.contains("credit") || value.contains("tabby") { return .credit }
        if value.contains("debit") { return .debit }
        return .current
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        let result = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        guard let value, !(value is NSNull) else { return nil }
        return Decimal(string: String(describing: value), locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        return Int(String(describing: value))
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = string(value) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = fractional.date(from: text) { return result }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: text)
    }
}
