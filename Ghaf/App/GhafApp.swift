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

            Text("Ghaf")
                .font(.system(size: 34, weight: .bold))
                .padding()
        }
        .modelContainer(modelContainer)
    }
}
