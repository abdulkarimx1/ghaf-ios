import Foundation
import SwiftData

@MainActor
enum GhafPersistence {
    private static var cachedContainer: ModelContainer?

    /// Reuse one container inside the app process so App Intents and SwiftUI
    /// resolve the same persistent store and observe each other's writes.
    static func makeContainer() throws -> ModelContainer {
        if let cachedContainer {
            return cachedContainer
        }
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

        let container = try ModelContainer(for: schema, configurations: [configuration])
        cachedContainer = container
        return container
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
