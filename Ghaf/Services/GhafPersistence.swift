import Foundation
import SwiftData

@MainActor
enum GhafPersistence {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            GhafTransaction.self,
            GhafSettings.self,
            GhafAccount.self,
            MerchantCategoryRule.self
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
