import SwiftUI
import SwiftData

@main
struct GhafApp: App {

    private let modelContainer: ModelContainer

    init() {

        do {

            modelContainer = try GhafPersistence.makeContainer()

        } catch {

            fatalError(
                "Failed to initialize Ghaf database: \(error)"
            )
        }
    }

    var body: some Scene {

        WindowGroup {

            GhafRootView()
        }
        .modelContainer(modelContainer)
    }
}
