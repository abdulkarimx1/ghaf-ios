import Foundation
import SwiftData
import OSLog
import GhafCore

@MainActor
enum GhafPersistence {
    private static var sharedContainer: ModelContainer?

    static func shared() throws -> ModelContainer {
        if let sharedContainer {
            cleanMerchantDataIfNeeded(in: sharedContainer.mainContext)
            migrateLegacyCategories(in: sharedContainer.mainContext)
            return sharedContainer
        }
        let container = try makeContainer()
        sharedContainer = container
        cleanMerchantDataIfNeeded(in: container.mainContext)
        migrateLegacyCategories(in: container.mainContext)
        return container
    }

    private static func cleanMerchantDataIfNeeded(in context: ModelContext) {
        // v2: also strips a trailing "using … card" clause (re-runs the same idempotent cleanup).
        let flag = "ghaf.migration.merchantClean.v2"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        do {
            let cleaned = try cleanMerchantData(in: context, save: false)
            try context.save()
            UserDefaults.standard.set(true, forKey: flag)
            Logger(subsystem: "Ghaf", category: "Persistence").info("\(cleaned, privacy: .public)")
        } catch {
            context.rollback()
            UserDefaults.standard.set(true, forKey: flag)
            Logger(subsystem: "Ghaf", category: "Persistence").error("Merchant cleanup migration failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    @discardableResult
    static func cleanMerchantData(in context: ModelContext, save: Bool = true) throws -> Int {
        let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
#if DEBUG
        let manualMerchants = Dictionary(uniqueKeysWithValues: transactions.filter {
            ["manual-", "manual-adjust-", "salary-", "transfer-", "voice-"].contains(where: $0.fingerprint.hasPrefix)
        }.map { ($0.id, $0.merchant) })
#endif
        var cleaned = 0
        for transaction in transactions {
            let fingerprint = transaction.fingerprint
            guard !["manual-", "manual-adjust-", "salary-", "transfer-", "voice-"].contains(where: fingerprint.hasPrefix),
                  transaction.bank != nil || ["wallet-", "file-", "expend-"].contains(where: fingerprint.hasPrefix) else { continue }
            // shortcut: older rows lack a merchant-edit marker; add one before cleaning edited automated entries.
            guard let merchant = transaction.merchant else { continue }
            let value = MerchantName.clean(merchant)
            let baseline = merchant.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if value != baseline { transaction.merchant = value; cleaned += 1 }
        }
#if DEBUG
        assert(transactions.filter { manualMerchants[$0.id] != nil }.allSatisfy { manualMerchants[$0.id] == $0.merchant },
               "Merchant migration changed a manual transaction")
#endif
        try MerchantCategorizer.rekeyRules(context: context, save: false)
        if save { try context.save() }
        return cleaned
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

#if DEBUG
    static func makeSettingsAuditContainer() throws -> ModelContainer {
        let schema = Schema([GhafTransaction.self, GhafSettings.self, GhafAccount.self,
                             MerchantCategoryRule.self, GhafSubscription.self, GhafChat.self, GhafMemory.self])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GhafSettingsPersistenceAudit.store")
        let configuration = ModelConfiguration("GhafSettingsPersistenceAudit", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
#endif

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

    private static func migrateLegacyCategories(in context: ModelContext) {
        let key = "ghaf.migration.categoryAliases.v1"
        guard !UserDefaults.standard.bool(forKey: key),
              let settings = try? settings(in: context),
              let transactions = try? context.fetch(FetchDescriptor<GhafTransaction>()) else { return }
        var changed = 0
        for transaction in transactions {
            let canonical = CategoryTaxonomy.currentCategoryName(for: transaction.category, available: settings.categories)
            if canonical != transaction.category { transaction.category = canonical; changed += 1 }
        }
        do {
            if changed > 0 { try context.save() }
            UserDefaults.standard.set(true, forKey: key)
            Logger(subsystem: "Ghaf", category: "Persistence").info("Category migration updated \(changed, privacy: .public) transactions")
        } catch {
            context.rollback()
            Logger(subsystem: "Ghaf", category: "Persistence").error("Category alias migration failed: \(error.localizedDescription, privacy: .private)")
        }
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
