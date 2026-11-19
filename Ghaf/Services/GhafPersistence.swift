import Foundation
import SwiftData
import OSLog
import GhafCore

@MainActor
enum GhafPersistence {
    private static var sharedContainer: ModelContainer?

    static func shared() throws -> ModelContainer {
        if let sharedContainer {
            cleanMerchantDataIfNeeded(in: ModelContext(sharedContainer))
            return sharedContainer
        }
        let container = try makeContainer()
        sharedContainer = container
        cleanMerchantDataIfNeeded(in: ModelContext(container))
        return container
    }

    private static func cleanMerchantDataIfNeeded(in context: ModelContext) {
        // v2: also strips a trailing "using … card" clause (re-runs the same idempotent cleanup).
        let flag = "ghaf.migration.merchantClean.v2"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        do {
            let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
            var cleaned = 0
            for transaction in transactions {
                guard let merchant = transaction.merchant else { continue }
                let value = MerchantName.clean(merchant)
                let baseline = merchant.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if value != baseline { transaction.merchant = value; cleaned += 1 }
            }
            try MerchantCategorizer.rekeyRules(context: context, save: false)
            try context.save()
            UserDefaults.standard.set(true, forKey: flag)
            Logger(subsystem: "Ghaf", category: "Persistence").info("\(cleaned, privacy: .public)")
        } catch {
            context.rollback()
        }
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            GhafTransaction.self,
            GhafSettings.self,
            GhafAccount.self,
            MerchantCategoryRule.self,
            GhafSubscription.self,
            GhafChat.self,
            GhafMemory.self // Additive: existing records remain untouched.
        ])

        let configuration = ModelConfiguration(
            "Ghaf",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func settings(in context: ModelContext) throws -> GhafSettings {
        var descriptor = FetchDescriptor<GhafSettings>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = GhafSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    static func ensureDefaultCashWallet(
        in context: ModelContext,
        currency: String
    ) throws -> GhafAccount {
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        if let existing = accounts.first(where: { !$0.isArchived && $0.type == .cash }) {
            return existing
        }

        let wallet = GhafAccount(
            name: "Cash wallet",
            accountType: .cash,
            currency: currency,
            openingBalance: 0,
            isPrimary: accounts.isEmpty,
            sortOrder: accounts.count
        )
        context.insert(wallet)
        try context.save()
        return wallet
    }
}
