import Foundation
import SwiftData
import GhafCore

private struct GhafBackupPayload: Codable {

    var version: Int
    var exportedAt: Date

    var settings: GhafSettingsBackup

    var transactions: [GhafTransactionBackup]

    var merchantRules: [GhafMerchantRuleBackup]
}

private struct GhafSettingsBackup: Codable {

    var userName: String
    var currency: String

    var monthlyIncome: Decimal
    var fixedCommitments: Decimal

    var themeName: String
    var appearanceMode: String
    var budgetMode: String

    var categories: [String]
    var categoryBudgets: [String: Decimal]

    var hasCompletedOnboarding: Bool
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
    var confidence: Double

    var bank: String?

    var needsReview: Bool
    var isReversal: Bool

    var note: String?
    var createdAt: Date
}

private struct GhafMerchantRuleBackup: Codable {

    var normalizedMerchant: String
    var category: String
    var updatedAt: Date
}

enum GhafBackupError: LocalizedError {

    case unsupportedVersion

    var errorDescription: String? {

        switch self {

        case .unsupportedVersion:
            return "This backup version is not supported."
        }
    }
}

@MainActor
enum GhafBackupService {

    static func export(
        context: ModelContext
    ) throws -> URL {

        let settings = try context.fetch(
            FetchDescriptor<GhafSettings>()
        ).first ?? GhafSettings()

        let transactions = try context.fetch(
            FetchDescriptor<GhafTransaction>()
        )

        let rules = try context.fetch(
            FetchDescriptor<MerchantCategoryRule>()
        )

        let settingsBackup = GhafSettingsBackup(
            userName: settings.userName,
            currency: settings.currency,
            monthlyIncome: settings.monthlyIncome,
            fixedCommitments: settings.fixedCommitments,
            themeName: settings.themeName,
            appearanceMode: settings.appearanceMode,
            budgetMode: settings.budgetMode,
            categories: settings.categories,
            categoryBudgets: settings.categoryBudgets,
            hasCompletedOnboarding: settings.hasCompletedOnboarding
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
                confidence: transaction.confidence,
                bank: transaction.bank,
                needsReview: transaction.needsReview,
                isReversal: transaction.isReversal,
                note: transaction.note,
                createdAt: transaction.createdAt
            )
        }

        let ruleBackups = rules.map { rule in

            GhafMerchantRuleBackup(
                normalizedMerchant: rule.normalizedMerchant,
                category: rule.category,
                updatedAt: rule.updatedAt
            )
        }

        let payload = GhafBackupPayload(
            version: 1,
            exportedAt: Date(),
            settings: settingsBackup,
            transactions: transactionBackups,
            merchantRules: ruleBackups
        )

        let encoder = JSONEncoder()

        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Ghaf-Backup-\(Int(Date().timeIntervalSince1970)).json"
            )

        try data.write(
            to: url,
            options: .atomic
        )

        return url
    }

    /// Replaces current Ghaf data with the selected backup.
    static func restore(
        from url: URL,
        context: ModelContext
    ) throws {

        let accessGranted = url.startAccessingSecurityScopedResource()

        defer {

            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(
            GhafBackupPayload.self,
            from: data
        )

        guard payload.version == 1 else {
            throw GhafBackupError.unsupportedVersion
        }

        // Delete existing transactions.
        let oldTransactions = try context.fetch(
            FetchDescriptor<GhafTransaction>()
        )

        oldTransactions.forEach {
            context.delete($0)
        }

        // Delete old settings.
        let oldSettings = try context.fetch(
            FetchDescriptor<GhafSettings>()
        )

        oldSettings.forEach {
            context.delete($0)
        }

        // Delete existing merchant rules.
        let oldRules = try context.fetch(
            FetchDescriptor<MerchantCategoryRule>()
        )

        oldRules.forEach {
            context.delete($0)
        }

        // Restore settings.
        let source = payload.settings

        let settings = GhafSettings(
            userName: source.userName,
            currency: source.currency,
            monthlyIncome: source.monthlyIncome,
            fixedCommitments: source.fixedCommitments,
            themeName: source.themeName,
            appearanceMode: source.appearanceMode,
            budgetMode: source.budgetMode,
            hasCompletedOnboarding: source.hasCompletedOnboarding
        )

        settings.categories = source.categories
        settings.categoryBudgets = source.categoryBudgets

        context.insert(settings)

        // Restore transactions.
        for item in payload.transactions {

            let parsed = ParsedTransaction(
                amount: item.amount,
                currency: item.currency,
                merchant: item.merchant,
                date: item.date,
                direction: TransactionDirection(
                    rawValue: item.direction
                ) ?? .debit,
                confidence: item.confidence,
                bank: item.bank
            )

            let transaction = GhafTransaction(
                fingerprint: item.fingerprint,
                parsed: parsed,
                category: item.category,
                needsReview: item.needsReview,
                isReversal: item.isReversal
            )

            transaction.id = item.id
            transaction.note = item.note
            transaction.createdAt = item.createdAt

            context.insert(transaction)
        }

        // Restore learned merchant rules.
        for item in payload.merchantRules {

            let rule = MerchantCategoryRule(
                normalizedMerchant: item.normalizedMerchant,
                category: item.category
            )

            rule.updatedAt = item.updatedAt

            context.insert(rule)
        }

        try context.save()
    }
}
