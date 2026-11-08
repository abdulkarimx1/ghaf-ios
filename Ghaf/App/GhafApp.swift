import SwiftUI
import SwiftData
import UIKit

@main
struct GhafApp: App {

    private let modelContainer: ModelContainer

    init() {
        UIScrollView.appearance().bounces = false
        UIScrollView.appearance().alwaysBounceVertical = false
        UIScrollView.appearance().alwaysBounceHorizontal = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        UIScrollView.appearance().showsVerticalScrollIndicator = false

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
