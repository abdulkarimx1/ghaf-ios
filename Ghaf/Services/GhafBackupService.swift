import Foundation
import SwiftData
import GhafCore
import CoreFoundation

private struct GhafBackupPayload: Codable {
    var version: Int
    var exportedAt: Date
    var settings: GhafSettingsBackup
    var transactions: [GhafTransactionBackup]
    var merchantRules: [GhafMerchantRuleBackup]
    var accounts: [GhafAccountBackup]?
    var subscriptions: [GhafSubscriptionBackup]?
    var glass: GhafGlassBackup?
    var memories: [GhafMemoryBackup]?
    var preferences: GhafBackupPreferences?
}

private struct GhafBackupPreferences: Codable {
    var version: Int
    var values: [String: GhafBackupPreference]
}

private enum GhafBackupPreference: Codable {
    case bool(Bool), string(String), integer(Int), double(Double), data(Data)
}

private struct GhafGlassBackup: Codable {
    var enabled: Bool
    var intensity: String
    var grain: Bool
    var glow: Bool
    var tilt: Bool
}

private struct GhafSubscriptionBackup: Codable {
    var id: UUID
    var name: String
    var amount: Decimal
    var currency: String
    var billingCycle: String
    var nextPaymentDate: Date
    var category: String
    var accountID: UUID?
    var reminderDays: Int
    var isActive: Bool
    var needsConfirmation: Bool
    var notes: String?
    /// A pending price-rise prompt; optional so backups from before 1.19 still import.
    var proposedAmount: Decimal?
    var createdAt: Date?
}

private struct GhafSettingsBackup: Codable {
    var id: UUID?
    var userName: String
    var languageCode: String?
    var hasSeenAutomationIntro: Bool?
    var currency: String
    var monthlyIncome: Decimal
    var fixedCommitments: Decimal
    var themeName: String
    var appearanceMode: String
    var budgetMode: String
    var categories: [String]
    var categoryMeta: [String: GhafCategoryMeta]?
    var categoryBudgets: [String: Decimal]
    var hasCompletedOnboarding: Bool

    var balanceSetupMode: String?
    var salaryEnabled: Bool?
    var salaryDay: Int?
    var salaryAmount: Decimal?
    var salaryCurrency: String?
    var salaryAccountID: UUID?
    var lastSalaryDecisionKey: String?
    var salaryReminderEnabled: Bool?
    var biometricLockEnabled: Bool?
    var createdAt: Date?
}

private struct GhafTransactionBackup: Codable {
    var id: UUID
    var fingerprint: String
    var amount: Decimal
    var currency: String
    var merchant: String?
    var date: Date
    var direction: String
    var category: String
    var subcategory: String?
    var confidence: Double
    var bank: String?
    var needsReview: Bool
    var isReversal: Bool
    var note: String?
    var createdAt: Date
    var accountID: UUID?
    var originalAmount: Decimal?
    var originalCurrency: String?
    var exchangeRate: Decimal?
    var exchangeRateDate: Date?
}

private struct GhafMemoryBackup: Codable {
    var id: UUID
    var text: String
    var kind: String
    var source: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
}

private struct GhafAccountBackup: Codable {
    var id: UUID
    var name: String
    var institution: String?
    var accountType: String
    var currency: String
    var openingBalance: Decimal
    var openingDate: Date
    var creditLimit: Decimal?
    var lastFourDigits: String?
    var isArchived: Bool
    var includeInTotal: Bool?
    var cardDesign: String?
    var isPrimary: Bool
    var sortOrder: Int
    var notes: String?
    var createdAt: Date
}

private struct GhafMerchantRuleBackup: Codable {
    var normalizedMerchant: String
    var category: String
    var subcategory: String?
    var hits: Int?
    var updatedAt: Date
}

enum GhafBackupError: LocalizedError {
    case unsupportedVersion
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            "This backup version is not supported."
        case .invalidBackup(let summary):
            "This backup is damaged: \(summary)."
        }
    }
}

@MainActor
enum GhafBackupService {
    static func export(context: ModelContext) throws -> URL {
        let settings = try context.fetch(FetchDescriptor<GhafSettings>()).first ?? GhafSettings()
        let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
        let rules = try context.fetch(FetchDescriptor<MerchantCategoryRule>())
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        let subscriptions = try context.fetch(FetchDescriptor<GhafSubscription>())
        let memories = try context.fetch(FetchDescriptor<GhafMemory>())

        let settingsBackup = GhafSettingsBackup(
            id: settings.id,
            userName: settings.userName,
            languageCode: settings.languageCode,
            hasSeenAutomationIntro: settings.hasSeenAutomationIntro,
            currency: settings.currency,
            monthlyIncome: settings.monthlyIncome,
            fixedCommitments: settings.fixedCommitments,
            themeName: settings.themeName,
            appearanceMode: settings.appearanceMode,
            budgetMode: settings.budgetMode,
            categories: settings.categories,
            categoryMeta: settings.categoryMeta,
            categoryBudgets: settings.categoryBudgets,
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            balanceSetupMode: settings.balanceSetupMode,
            salaryEnabled: settings.salaryEnabled,
            salaryDay: settings.salaryDay,
            salaryAmount: settings.salaryAmount,
            salaryCurrency: settings.salaryCurrency,
            salaryAccountID: settings.salaryAccountID,
            lastSalaryDecisionKey: settings.lastSalaryDecisionKey,
            salaryReminderEnabled: settings.salaryReminderEnabled,
            biometricLockEnabled: settings.biometricLockEnabled,
            createdAt: settings.createdAt
        )

        let transactionBackups = transactions.map { transaction in
            GhafTransactionBackup(
                id: transaction.id,
                fingerprint: transaction.fingerprint,
                amount: transaction.amount,
                currency: transaction.currency,
                merchant: transaction.merchant,
                date: transaction.date,
                direction: transaction.direction,
                category: transaction.category,
                subcategory: transaction.subcategory,
                confidence: transaction.confidence,
                bank: transaction.bank,
                needsReview: transaction.needsReview,
                isReversal: transaction.isReversal,
                note: transaction.note,
                createdAt: transaction.createdAt,
                accountID: transaction.accountID,
                originalAmount: transaction.originalAmount,
                originalCurrency: transaction.originalCurrency,
                exchangeRate: transaction.exchangeRate,
                exchangeRateDate: transaction.exchangeRateDate
            )
        }

        let accountBackups = accounts.map { account in
            GhafAccountBackup(
                id: account.id,
                name: account.name,
                institution: account.institution,
                accountType: account.accountType,
                currency: account.currency,
                openingBalance: account.openingBalance,
                openingDate: account.openingDate,
                creditLimit: account.creditLimit,
                lastFourDigits: account.lastFourDigits,
                isArchived: account.isArchived,
                includeInTotal: account.includeInTotal,
                cardDesign: account.cardDesign,
                isPrimary: account.isPrimary,
                sortOrder: account.sortOrder,
                notes: account.notes,
                createdAt: account.createdAt
            )
        }

        let ruleBackups = rules.map {
            GhafMerchantRuleBackup(
                normalizedMerchant: $0.normalizedMerchant,
                category: $0.category,
                subcategory: $0.subcategory,
                hits: $0.hits,
                updatedAt: $0.updatedAt
            )
        }

        let payload = GhafBackupPayload(
            version: 4,
            exportedAt: .now,
            settings: settingsBackup,
            transactions: transactionBackups,
            merchantRules: ruleBackups,
            accounts: accountBackups,
            subscriptions: subscriptions.map {
                GhafSubscriptionBackup(id: $0.id, name: $0.name, amount: $0.amount, currency: $0.currency,
                                       billingCycle: $0.billingCycle, nextPaymentDate: $0.nextPaymentDate,
                                       category: $0.category, accountID: $0.accountID, reminderDays: $0.reminderDays,
                                       isActive: $0.isActive, needsConfirmation: $0.needsConfirmation, notes: $0.notes,
                                       proposedAmount: $0.proposedAmount, createdAt: $0.createdAt)
            },
            glass: GhafGlassBackup(enabled: UserDefaults.standard.object(forKey: "ghaf.glass.enabled") as? Bool ?? true,
                                   intensity: UserDefaults.standard.string(forKey: "ghaf.glass.intensity") ?? "balanced",
                                   grain: UserDefaults.standard.object(forKey: "ghaf.glass.grain") as? Bool ?? true,
                                   glow: UserDefaults.standard.object(forKey: "ghaf.glass.glow") as? Bool ?? true,
                                   tilt: UserDefaults.standard.object(forKey: "ghaf.glass.tilt") as? Bool ?? true),
            memories: memories.map { .init(id: $0.id, text: $0.text, kind: $0.kind, source: $0.source,
                                           createdAt: $0.createdAt, updatedAt: $0.updatedAt, lastUsedAt: $0.lastUsedAt) },
            preferences: exportPreferences()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ghaf-Backup-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Replaces current Ghaf data with a supported v1–v4 backup. Chats remain local and are not in the backup format.
    @discardableResult
    static func restore(from url: URL, context: ModelContext) throws -> Int {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GhafBackupPayload.self, from: data)

        guard (1...4).contains(payload.version) else {
            throw GhafBackupError.unsupportedVersion
        }
        if let preferences = payload.preferences, preferences.version != 1 {
            throw GhafBackupError.unsupportedVersion
        }

        let problems = BackupIntegrity.validate(
            transactionIDs: payload.transactions.map(\.id),
            fingerprints: payload.transactions.map(\.fingerprint),
            accountIDs: payload.accounts?.map(\.id),
            subscriptionIDs: payload.subscriptions?.map(\.id) ?? [],
            merchantRuleKeys: payload.merchantRules.map(\.normalizedMerchant),
            accountReferences: payload.transactions.map(\.accountID) + (payload.subscriptions ?? []).map(\.accountID) + [payload.settings.salaryAccountID]
        )
        let blockingProblems = problems.filter {
            if case .unknownAccountReference = $0 { return false }
            return true
        }
        if !blockingProblems.isEmpty {
            throw GhafBackupError.invalidBackup("\(blockingProblems.count) integrity issue(s) found")
        }
        let availableAccountIDs = payload.accounts.map { Set($0.map(\.id)) }
        let unassignedCount = BackupIntegrity.missingAccountReferences(
            accountIDs: payload.accounts?.map(\.id),
            references: payload.transactions.map(\.accountID) + (payload.subscriptions ?? []).map(\.accountID) + [payload.settings.salaryAccountID]
        ).count

        try context.fetch(FetchDescriptor<GhafTransaction>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<GhafAccount>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<GhafSettings>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MerchantCategoryRule>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<GhafMemory>()).forEach { context.delete($0) }
        let oldSubscriptions = payload.subscriptions == nil ? [] : try context.fetch(FetchDescriptor<GhafSubscription>())
        // Read ids now: a deleted model's properties can't be read after the save.
        let oldReminderIDs = oldSubscriptions.map(\.id)
        oldSubscriptions.forEach { context.delete($0) }

        let source = payload.settings
        let settings = GhafSettings(
            userName: source.userName,
            languageCode: source.languageCode ?? "en",
            hasSeenAutomationIntro: source.hasSeenAutomationIntro ?? false,
            currency: source.currency,
            monthlyIncome: source.monthlyIncome,
            fixedCommitments: source.fixedCommitments,
            themeName: source.themeName,
            appearanceMode: source.appearanceMode,
            budgetMode: source.budgetMode,
            hasCompletedOnboarding: source.hasCompletedOnboarding,
            balanceSetupMode: source.balanceSetupMode ?? "zero",
            salaryEnabled: source.salaryEnabled ?? false,
            salaryDay: source.salaryDay,
            salaryAmount: source.salaryAmount,
            salaryCurrency: source.salaryCurrency,
            salaryAccountID: availableAccountIDs.map { ids in
                guard let id = source.salaryAccountID, !ids.contains(id) else { return source.salaryAccountID }
                return nil
            } ?? source.salaryAccountID,
            lastSalaryDecisionKey: source.lastSalaryDecisionKey,
            salaryReminderEnabled: source.salaryReminderEnabled ?? false,
            biometricLockEnabled: source.biometricLockEnabled ?? false
        )
        settings.id = source.id ?? settings.id
        settings.createdAt = source.createdAt ?? settings.createdAt
        settings.categories = source.categories
        settings.categoryMeta = source.categoryMeta ?? [:]
        settings.categoryBudgets = source.categoryBudgets
        context.insert(settings)

        for item in payload.accounts ?? [] {
            let account = GhafAccount(
                id: item.id,
                name: item.name,
                institution: item.institution,
                accountType: GhafAccountType(rawValue: item.accountType) ?? .cash,
                currency: item.currency,
                openingBalance: item.openingBalance,
                openingDate: item.openingDate,
                creditLimit: item.creditLimit,
                lastFourDigits: item.lastFourDigits,
                isArchived: item.isArchived,
                isPrimary: item.isPrimary,
                sortOrder: item.sortOrder,
                notes: item.notes
            )
            account.createdAt = item.createdAt
            account.includeInTotal = item.includeInTotal ?? true
            account.cardDesign = item.cardDesign
            context.insert(account)
        }

        for item in payload.transactions {
            let parsed = ParsedTransaction(
                amount: item.amount,
                currency: item.currency,
                merchant: item.merchant,
                date: item.date,
                direction: TransactionDirection(rawValue: item.direction) ?? .debit,
                confidence: item.confidence,
                bank: item.bank
            )

            let transaction = GhafTransaction(
                fingerprint: item.fingerprint,
                parsed: parsed,
                category: item.category,
                needsReview: item.needsReview,
                isReversal: item.isReversal,
                accountID: {
                    guard let ids = availableAccountIDs, let id = item.accountID, !ids.contains(id) else { return item.accountID }
                    return nil
                }()
            )
            transaction.id = item.id
            transaction.note = item.note
            transaction.subcategory = item.subcategory
            transaction.createdAt = item.createdAt
            transaction.originalAmount = item.originalAmount
            transaction.originalCurrency = item.originalCurrency
            transaction.exchangeRate = item.exchangeRate
            transaction.exchangeRateDate = item.exchangeRateDate
            context.insert(transaction)
        }

        for item in payload.merchantRules {
            let rule = MerchantCategoryRule(
                normalizedMerchant: item.normalizedMerchant,
                category: item.category
            )
            rule.updatedAt = item.updatedAt
            rule.subcategory = item.subcategory
            rule.hits = item.hits ?? 1
            context.insert(rule)
        }

        for item in payload.subscriptions ?? [] {
            let subscription = GhafSubscription(
                id: item.id, name: item.name, amount: item.amount, currency: item.currency,
                billingCycle: GhafBillingCycle(rawValue: item.billingCycle) ?? .monthly,
                nextPaymentDate: item.nextPaymentDate, category: item.category, accountID: {
                    guard let ids = availableAccountIDs, let id = item.accountID, !ids.contains(id) else { return item.accountID }
                    return nil
                }(),
                reminderDays: item.reminderDays, isActive: item.isActive, notes: item.notes
            )
            subscription.needsConfirmation = item.needsConfirmation
            subscription.proposedAmount = item.proposedAmount
            subscription.createdAt = item.createdAt ?? subscription.createdAt
            context.insert(subscription)
        }

        for item in payload.memories ?? [] {
            let memory = GhafMemory(text: item.text, kind: item.kind, source: item.source)
            memory.id = item.id; memory.createdAt = item.createdAt; memory.updatedAt = item.updatedAt; memory.lastUsedAt = item.lastUsedAt
            context.insert(memory)
        }

        #if DEBUG
        let restoredTransactions = try context.fetch(FetchDescriptor<GhafTransaction>())
        assert(restoredTransactions.allSatisfy { transaction in
            transaction.accountID.map { availableAccountIDs?.contains($0) ?? true } ?? true
        }, "Restored records still contain a dangling account reference")
        #endif

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        oldReminderIDs.forEach { GhafSubscriptionReminderService.cancel(id: $0) }
        if let preferences = payload.preferences, preferences.version == 1 {
            restorePreferences(preferences)
        } else if let glass = payload.glass {
            preferenceKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
            restoreGlass(glass)
        } else {
            preferenceKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        for subscription in try context.fetch(FetchDescriptor<GhafSubscription>()) where subscription.isActive {
            GhafSubscriptionReminderService.schedule(subscription, language: settings.languageCode)
        }
        return unassignedCount
    }

    #if DEBUG
    static func debugRoundTripCheck(context: ModelContext) async throws -> String {
        struct Snapshot: Equatable {
            var counts: [Int]
            var settings: [String]
            var accounts: [String]
            var transactions: [String]
            var subscriptions: [String]
            var rules: [String]
            var memories: [String]
            var preferences: Data
        }
        func json<T: Encodable>(_ value: T) throws -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        func snapshot() throws -> Snapshot {
            let settings = try context.fetch(FetchDescriptor<GhafSettings>())
            let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
            let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
            let subscriptions = try context.fetch(FetchDescriptor<GhafSubscription>())
            let rules = try context.fetch(FetchDescriptor<MerchantCategoryRule>())
            let memories = try context.fetch(FetchDescriptor<GhafMemory>())
            let preferenceEncoder = JSONEncoder(); preferenceEncoder.outputFormatting = [.sortedKeys]
            return Snapshot(
                counts: [settings.count, accounts.count, transactions.count, subscriptions.count, rules.count, memories.count],
                settings: try settings.map { "\($0.id)|\($0.themeName)|\($0.appearanceMode)|\($0.currency)|\($0.languageCode)|\($0.categories)|\(try json($0.categoryBudgets))|\(try json($0.categoryMeta))" }.sorted(),
                accounts: accounts.map { "\($0.id)|\($0.name)|\($0.institution ?? "")|\($0.cardDesign ?? "")|\($0.isArchived)|\($0.sortOrder)|\($0.openingBalance)|\($0.openingDate)|\($0.lastFourDigits ?? "")|\($0.creditLimit ?? 0)" }.sorted(),
                transactions: transactions.map { "\($0.id)|\($0.fingerprint)|\($0.amount)|\($0.originalAmount ?? 0)|\($0.originalCurrency ?? "")|\($0.exchangeRate ?? 0)|\($0.exchangeRateDate?.timeIntervalSince1970 ?? 0)" }.sorted(),
                subscriptions: subscriptions.map { "\($0.id)|\($0.name)|\($0.amount)|\($0.billingCycle)|\($0.nextPaymentDate.timeIntervalSince1970)|\($0.createdAt.timeIntervalSince1970)" }.sorted(),
                rules: rules.map { "\($0.normalizedMerchant)|\($0.category)|\($0.subcategory ?? "")|\($0.hits)|\($0.updatedAt.timeIntervalSince1970)" }.sorted(),
                memories: memories.map { "\($0.id)|\($0.text)|\($0.kind)|\($0.source)|\($0.createdAt.timeIntervalSince1970)|\($0.updatedAt.timeIntervalSince1970)|\($0.lastUsedAt?.timeIntervalSince1970 ?? 0)" }.sorted(),
                preferences: try preferenceEncoder.encode(exportPreferences())
            )
        }

        print("Ghaf backup round-trip: exporting")
        let expected = try snapshot()
        let exported = try export(context: context)
        let data = try Data(contentsOf: exported)
        try? FileManager.default.removeItem(at: exported)
        print("Ghaf backup round-trip: resetting")
        let warnings = try await GhafResetService.run(context: context)
        print("Ghaf backup round-trip: restoring")
        let recoveryURL = FileManager.default.temporaryDirectory.appendingPathComponent("GhafRoundTrip-\(UUID().uuidString).json")
        try data.write(to: recoveryURL, options: .atomic)
        do {
            try restore(from: recoveryURL, context: context)
            print("Ghaf backup round-trip: comparing")
            guard try snapshot() == expected else {
                throw GhafBackupError.invalidBackup("round-trip model counts or fields differ; recovery file: \(recoveryURL.path)")
            }
            try FileManager.default.removeItem(at: recoveryURL)
            return warnings.isEmpty ? "Counts and key fields matched." : "Counts and key fields matched; reset cleanup warnings: \(warnings.joined(separator: ", "))"
        } catch {
            throw GhafBackupError.invalidBackup("round-trip failed; recovery file: \(recoveryURL.path); \(error.localizedDescription)")
        }
    }
    #endif

    private static let preferenceKeys = [
        "ghaf.hideBalances", "ghaf.weekStart", "ghaf.glass.enabled", "ghaf.glass.intensity", "ghaf.glass.grain",
        "ghaf.glass.glow", "ghaf.glass.tilt", "ghaf.ai.cloudEnabled", "ghaf.ai.modelLearning", "ghaf.ai.memoryEnabled",
        "ghaf.ai.speakReplies", "ghaf.notify.autoTransaction", "ghaf.notify.morning",
        "ghaf.notify.evening", "ghaf.notify.weekly", "ghaf.liveActivity", "ghaf.places.byMerchant",
        "ghaf.places.byTransaction", "ghaf.voice.learnedPause"
    ]

    private static func exportPreferences() -> GhafBackupPreferences {
        var values: [String: GhafBackupPreference] = [:]
        for key in preferenceKeys {
            guard let value = UserDefaults.standard.object(forKey: key) else { continue }
            if let data = value as? Data { values[key] = .data(data) }
            else if let string = value as? String { values[key] = .string(string) }
            else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { values[key] = .bool(number.boolValue) }
                else if CFNumberIsFloatType(number as CFNumber) { values[key] = .double(number.doubleValue) }
                else { values[key] = .integer(number.intValue) }
            }
        }
        return GhafBackupPreferences(version: 1, values: values)
    }

    private static func restorePreferences(_ preferences: GhafBackupPreferences) {
        preferenceKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        for (key, value) in preferences.values where preferenceKeys.contains(key) {
            switch value {
            case .bool(let value): UserDefaults.standard.set(value, forKey: key)
            case .string(let value): UserDefaults.standard.set(value, forKey: key)
            case .integer(let value): UserDefaults.standard.set(value, forKey: key)
            case .double(let value): UserDefaults.standard.set(value, forKey: key)
            case .data(let value): UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    private static func restoreGlass(_ glass: GhafGlassBackup) {
        UserDefaults.standard.set(glass.enabled, forKey: "ghaf.glass.enabled")
        UserDefaults.standard.set(glass.intensity, forKey: "ghaf.glass.intensity")
        UserDefaults.standard.set(glass.grain, forKey: "ghaf.glass.grain")
        UserDefaults.standard.set(glass.glow, forKey: "ghaf.glass.glow")
        UserDefaults.standard.set(glass.tilt, forKey: "ghaf.glass.tilt")
    }
}
