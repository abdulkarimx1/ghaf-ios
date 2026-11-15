import Foundation
import SwiftData
import GhafCore

private struct GhafBackupPayload: Codable {
    var version: Int
    var exportedAt: Date
    var settings: GhafSettingsBackup
    var transactions: [GhafTransactionBackup]
    var merchantRules: [GhafMerchantRuleBackup]
    var accounts: [GhafAccountBackup]?
    var subscriptions: [GhafSubscriptionBackup]?
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
}

private struct GhafSettingsBackup: Codable {
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

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            "This backup version is not supported."
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

        let settingsBackup = GhafSettingsBackup(
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
            biometricLockEnabled: settings.biometricLockEnabled
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
                accountID: transaction.accountID
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
            version: 3,
            exportedAt: .now,
            settings: settingsBackup,
            transactions: transactionBackups,
            merchantRules: ruleBackups,
            accounts: accountBackups,
            subscriptions: subscriptions.map {
                GhafSubscriptionBackup(id: $0.id, name: $0.name, amount: $0.amount, currency: $0.currency,
                                       billingCycle: $0.billingCycle, nextPaymentDate: $0.nextPaymentDate,
                                       category: $0.category, accountID: $0.accountID, reminderDays: $0.reminderDays,
                                       isActive: $0.isActive, needsConfirmation: $0.needsConfirmation, notes: $0.notes)
            }
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

    /// Replaces current Ghaf data with a v1, v2 or v3 backup. Subscriptions are only replaced when the backup has them.
    static func restore(from url: URL, context: ModelContext) throws {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GhafBackupPayload.self, from: data)

        guard (1...3).contains(payload.version) else {
            throw GhafBackupError.unsupportedVersion
        }

        try context.fetch(FetchDescriptor<GhafTransaction>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<GhafAccount>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<GhafSettings>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MerchantCategoryRule>()).forEach { context.delete($0) }
        if payload.subscriptions != nil {
            try context.fetch(FetchDescriptor<GhafSubscription>()).forEach {
                GhafSubscriptionReminderService.cancel($0)
                context.delete($0)
            }
        }

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
            salaryAccountID: source.salaryAccountID,
            lastSalaryDecisionKey: source.lastSalaryDecisionKey,
            salaryReminderEnabled: source.salaryReminderEnabled ?? false,
            biometricLockEnabled: source.biometricLockEnabled ?? false
        )
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
                accountID: item.accountID
            )
            transaction.id = item.id
            transaction.note = item.note
            transaction.subcategory = item.subcategory
            transaction.createdAt = item.createdAt
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
                nextPaymentDate: item.nextPaymentDate, category: item.category, accountID: item.accountID,
                reminderDays: item.reminderDays, isActive: item.isActive, notes: item.notes
            )
            subscription.needsConfirmation = item.needsConfirmation
            context.insert(subscription)
        }

        try context.save()
        for subscription in try context.fetch(FetchDescriptor<GhafSubscription>()) where subscription.isActive {
            GhafSubscriptionReminderService.schedule(subscription, language: settings.languageCode)
        }
    }
}
