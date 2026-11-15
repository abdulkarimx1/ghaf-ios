import Foundation
import SwiftData
import GhafCore

struct GhafExternalImportResult {
    let accountsImported: Int
    let transactionsImported: Int
    let skippedTransactions: Int
    let recurringRulesNotImported: Int
    let budgetsNotImported: Int
    let sourceName: String
}

enum GhafExpendImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case noValidWallets
    case invalidTransactionData
    case walletBalanceMismatch(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "The selected JSON file could not be read."
        case .unsupportedFormat: "This JSON file is not a supported Expend export."
        case .noValidWallets: "No valid wallets were found in the Expend export."
        case .invalidTransactionData: "The Expend transaction data is incomplete."
        case .walletBalanceMismatch(let name): "The imported ledger does not reconcile with the exported balance for wallet: \(name)."
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
        "reimbursements": "Other Income",
        "salary": "Salary",
        "fcfb4ee5-fc91-4680-8265-588a4b84639a": "Other Income",
        "transfer": "Transfers",
        "transfer-fee": "Fees",
        "debt-repayment": "Debt Repayment",
        "payable-debt-expansion": "Borrowed Money",
        "payable-debt-interest": "Interest",
        "payment-collection": "Other Income",
        "receivable-debt-expansion": "Lent Money",
        "receivable-debt-interest": "Interest",
        "adjustment-expense": "Other",
        "adjustment-income": "Other Income"
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

        // The user's own Expend categories (by id), with their subcategories, icons and colours.
        let categoryRows = ((root["categories"] as? [[String: Any]]) ?? []).filter { ($0["deleted"] as? Bool) != true }
        let categoryNames: [String: String] = Dictionary(categoryRows.compactMap { row -> (String, String)? in
            guard let id = string(row["_id"]), let name = string(row["name"]) else { return nil }
            return (id, transferCategoryIDs.contains(id) ? "Transfers" : id == "others-income" ? "Transfers received" : name)
        }, uniquingKeysWith: { first, _ in first })
        var categoryMeta: [String: GhafCategoryMeta] = [:]
        for row in categoryRows {
            guard let id = string(row["_id"]), let name = categoryNames[id] else { continue }
            categoryMeta[name, default: GhafCategoryMeta()].icon = symbol(forExpendIcon: string(row["icon"]))
            categoryMeta[name, default: GhafCategoryMeta()].color = string(row["color"])
        }
        for row in (root["subcategories"] as? [[String: Any]]) ?? [] where (row["deleted"] as? Bool) != true {
            guard let parent = string(row["mainCategoryID"]).flatMap({ categoryNames[$0] }),
                  let name = string(row["name"]),
                  categoryMeta[parent]?.subcategories.contains(name) != true else { continue }
            categoryMeta[parent, default: GhafCategoryMeta()].subcategories.append(name)
        }

        let walletsByID = Dictionary(
            uniqueKeysWithValues: validWalletRows.compactMap { row -> (String, [String: Any])? in
                guard let id = string(row["_id"]) else { return nil }
                return (id, row)
            }
        )

        let parsedTransactions = transactionRows.flatMap { row in
            prepare(row, walletIDs: walletIDs, walletsByID: walletsByID, subcategoryNames: subcategoryNames, categoryNames: categoryNames)
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
            let firstActivityDate = transactionRows
                .filter {
                    string($0["srcWallet"]) == sourceID ||
                    string($0["destWallet"]) == sourceID
                }
                .compactMap { date($0["dateCreated"]) }
                .min()
            let balanceStartDate = min(created, firstActivityDate ?? created)
            let institution = string(row["institution"])
            let archived = (row["isArchived"] as? Bool ?? false) || (row["deleted"] as? Bool ?? false)
            let primaryWalletID = string(profile["defaultWalletID"])
            let primary = primaryWalletID == sourceID || (primaryWalletID == nil && index == 0)
            let account = GhafAccount(
                id: accountID,
                name: name,
                institution: institution,
                accountType: type,
                currency: currency,
                openingBalance: openingBalance,
                openingDate: balanceStartDate,
                isArchived: archived,
                isPrimary: primary,
                sortOrder: integer(row["order"]) ?? index,
                notes: nil
            )
            account.includeInTotal = (row["showInBalance"] as? Bool) ?? true
            return account
        }

        // Keep the user's category order: categories they used first, then "Other".
        let usedCategories = parsedTransactions.map(\.category)
        var categoryValues: [String] = []
        for name in categoryRows.compactMap({ string($0["_id"]).flatMap { categoryNames[$0] } }) + usedCategories + ["Other"]
        where !categoryValues.contains(name) {
            categoryValues.append(name)
        }
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        for row in validWalletRows {
            guard let sourceID = string(row["_id"]),
                  let accountID = walletIDs[sourceID],
                  let account = accountByID[accountID] else { continue }
            let computed = parsedTransactions
                .filter { $0.accountID == accountID && $0.date >= account.openingDate }
                .reduce(account.openingBalance) { total, item in
                    item.direction == .credit ? total + item.amount : total - item.amount
                }
            let exported = decimal(row["currentAmount"]) ?? computed
            let difference = abs(NSDecimalNumber(decimal: computed - exported).doubleValue)
            if difference > 0.01 {
                throw GhafExpendImportError.walletBalanceMismatch(account.name)
            }
        }

        let currentRules = try context.fetch(FetchDescriptor<MerchantCategoryRule>())
        let recurringRows = ((root["recurringTransactions"] as? [[String: Any]]) ?? []).filter { string($0["type"]) == "expense" }
        var subscriptionsImported = 0
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
            settings.categories = categoryValues
            settings.categoryMeta = categoryMeta
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
                transaction.subcategory = item.subcategory
                context.insert(transaction)
            }

            // Learn merchant → category/subcategory from the whole history.
            let examples = parsedTransactions.filter { $0.direction == .debit && $0.category != "Transfers" }.compactMap { item in
                item.merchant.map { CategoryMatcher.Example(merchant: $0, category: item.category, subcategory: item.subcategory) }
            }
            for (key, rule) in CategoryMatcher.learn(from: examples) {
                let learned = MerchantCategoryRule(normalizedMerchant: key, category: rule.category)
                learned.subcategory = rule.subcategory
                learned.hits = rule.hits
                context.insert(learned)
            }

            let existingNames = Set(((try? context.fetch(FetchDescriptor<GhafSubscription>())) ?? []).map { CategoryMatcher.normalize($0.name) })
            for row in recurringRows {
                guard let item = subscription(from: row, walletIDs: walletIDs, walletsByID: walletsByID,
                                              categoryNames: categoryNames) else { continue }
                subscriptionsImported += 1  // already-tracked ones count as handled
                if !existingNames.contains(CategoryMatcher.normalize(item.name)) { context.insert(item) }
            }
            try context.save()
            for item in try context.fetch(FetchDescriptor<GhafSubscription>()) where item.isActive {
                GhafSubscriptionReminderService.schedule(item, language: languageCode)
            }
        } catch {
            context.rollback()
            throw error
        }

        let skipped = transactionRows.count - parsedTransactions.filter { !$0.isTransferMirror }.count
        return GhafExternalImportResult(
            accountsImported: accounts.count,
            transactionsImported: parsedTransactions.count,
            skippedTransactions: max(0, skipped),
            recurringRulesNotImported: max(0, ((root["recurringTransactions"] as? [[String: Any]])?.count ?? 0) - subscriptionsImported),
            budgetsNotImported: (root["budgets"] as? [[String: Any]])?.count ?? 0,
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
        let subcategory: String?
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
        subcategoryNames: [String: String],
        categoryNames: [String: String]
    ) -> [PreparedTransaction] {
        guard let sourceID = string(row["_id"]),
              let type = string(row["type"])?.lowercased(),
              let amount = decimal(row["amount"]), amount > 0 else { return [] }
        if row["deleted"] as? Bool == true { return [] }

        let date = date(row["dateCreated"]) ?? date(row["lastUpdated"]) ?? .now
        let rawCategory = string(row["category"]) ?? "other"
        let category = categoryNames[rawCategory] ?? categoryMap[rawCategory] ?? "Other"
        let subcategory = string(row["subcategory"]).flatMap { subcategoryNames[$0] }
        let merchant = string(row["name"])
        let sourceAccountID = string(row["srcWallet"]).flatMap { walletIDs[$0] }
        let sourceWallet = string(row["srcWallet"]).flatMap { walletsByID[$0] }
        let sourceCurrency = string(sourceWallet?["currencyCode"])?.uppercased() ?? "AED"
        let bank = string(sourceWallet?["institution"])
        let originalNotes = string(row["notes"])
        let noteParts = [originalNotes]
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
                subcategory: nil,
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
                subcategory: nil,
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
            subcategory: subcategory,
            note: note,
            bank: bank,
            accountID: sourceAccountID,
            needsReview: sourceAccountID == nil,
            isReversal: reversal,
            isTransferMirror: false
        )]
    }

    private static let transferCategoryIDs: Set<String> = ["transfer"]

    private static func subscription(
        from row: [String: Any],
        walletIDs: [String: UUID],
        walletsByID: [String: [String: Any]],
        categoryNames: [String: String]
    ) -> GhafSubscription? {
        guard let name = string(row["name"]), let amount = decimal(row["amount"]), amount > 0 else { return nil }
        let cycle: GhafBillingCycle
        switch string(row["recurrence"])?.lowercased() ?? "" {
        case let value where value.contains("week"): cycle = .weekly
        case let value where value.contains("quarter") || value.contains("3month"): cycle = .quarterly
        case let value where value.contains("year"): cycle = .yearly
        default: cycle = .monthly
        }
        let wallet = string(row["srcWallet"])
        return GhafSubscription(
            name: name,
            amount: amount,
            currency: string(wallet.flatMap { walletsByID[$0] }?["currencyCode"])?.uppercased() ?? "AED",
            billingCycle: cycle,
            nextPaymentDate: date(row["nextTransactionDate"]) ?? cycle.nextDate(after: .now),
            category: string(row["category"]).flatMap { categoryNames[$0] } ?? "Subscriptions",
            accountID: wallet.flatMap { walletIDs[$0] },
            notes: "Imported from Expend"
        )
    }

    /// Expend icon names → SF Symbols.
    private static func symbol(forExpendIcon icon: String?) -> String? {
        switch icon {
        case "spoonFork": "fork.knife"
        case "car": "car.fill"
        case "shoppingCart": "cart.fill"
        case "health": "heart.fill"
        case "shoppingBag": "bag.fill"
        case "lightBulb": "lightbulb.fill"
        case "dice": "dice.fill"
        case "bills": "doc.text.fill"
        case "coin": "dollarsign.circle.fill"
        case "coinStack": "banknote.fill"
        case "wallet": "wallet.pass.fill"
        case "transfer": "arrow.left.arrow.right"
        case "adjustment": "slider.horizontal.3"
        case "stonks": "chart.line.uptrend.xyaxis"
        case "borrow": "arrow.down.circle.fill"
        case "lend": "arrow.up.circle.fill"
        case "others": "ellipsis.circle.fill"
        default: nil
        }
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
