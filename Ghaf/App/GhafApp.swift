import SwiftUI
import SwiftData
import UIKit

@main
struct GhafApp: App {

    private let modelContainer: ModelContainer
    @AppStorage(GhafFormat.hideBalancesKey) private var hideBalances = false

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
                .modifier(GhafTiltLifecycle())
                .onAppear { DispatchQueue.main.async { GhafKeyboardDismisser.shared.install() } }
                // Widgets and Live Activities show purchase details, so they follow the hide toggle at once.
                .onChange(of: hideBalances) { _, hidden in
                    GhafWidgetSync.refresh(context: modelContainer.mainContext)
                    if hidden { Task { await GhafWidgetSync.endAll() } }
                }
        }
        .modelContainer(modelContainer)
    }
}
