import Foundation
import SwiftData

@MainActor
enum GhafPersistence {

    static func makeContainer() throws -> ModelContainer {

        let schema = Schema([
            GhafTransaction.self,
            GhafSettings.self,
            MerchantCategoryRule.self
        ])

        let configuration = ModelConfiguration(
            "Ghaf",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func settings(
        in context: ModelContext
    ) throws -> GhafSettings {

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
}
