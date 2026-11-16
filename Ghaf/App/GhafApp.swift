import SwiftUI
import SwiftData
import UIKit

@main
struct GhafApp: App {

    private let modelContainer: ModelContainer

    init() {
        // Native bounce stays on: it is part of iOS's fluid feel.
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        UIScrollView.appearance().showsVerticalScrollIndicator = false

        do {

            modelContainer = try GhafPersistence.shared()

        } catch {

            fatalError(
                "Failed to initialize Ghaf database: \(error)"
            )
        }
    }

    var body: some Scene {

        WindowGroup {

            GhafRootView()
                .onAppear { DispatchQueue.main.async { GhafKeyboardDismisser.shared.install() } }
        }
        .modelContainer(modelContainer)
    }
}
