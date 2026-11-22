import SwiftUI
import SwiftData
import UIKit

@main
struct GhafApp: App {
    @UIApplicationDelegateAdaptor(GhafAppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    @AppStorage(GhafFormat.hideBalancesKey) private var hideBalances = false

    init() {
#if DEBUG
        GhafLocalization.assertArabicDays()
#endif
        // Native bounce stays on: it is part of iOS's fluid feel.
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        UIScrollView.appearance().showsVerticalScrollIndicator = false

        do {
#if DEBUG
            if GhafScreenshotFixture.enabled {
                modelContainer = try GhafScreenshotFixture.makeContainer()
            } else {
                modelContainer = try GhafPersistence.shared()
            }
#else
            modelContainer = try GhafPersistence.shared()
#endif
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

final class GhafAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let ar = Locale.current.languageCode == "ar"
        application.shortcutItems = [
            UIApplicationShortcutItem(type: "com.ghaf.app.feedback", localizedTitle: ar ? "تحذف غاف؟ أخبرنا بالسبب" : "Deleting? Tell us why",
                                      localizedSubtitle: ar ? "أرسل ملاحظاتك قبل الحذف" : "Send feedback before you delete",
                                      icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil"), userInfo: nil),
            UIApplicationShortcutItem(type: "com.ghaf.app.goodbye-offer", localizedTitle: ar ? "هدية قبل الرحيل" : "A gift before you go",
                                      localizedSubtitle: ar ? "خصم ٢٥٪ لمرة واحدة على Pro" : "One-time 25% off Pro",
                                      icon: UIApplicationShortcutIcon(systemImageName: "gift"), userInfo: nil)
        ]
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let destination = shortcutItem.type == "com.ghaf.app.feedback"
            ? GhafLinks.instagram
            : URL(string: "ghaf://pro")!
        if shortcutItem.type == "com.ghaf.app.goodbye-offer" {
            UserDefaults.standard.set(true, forKey: "ghaf.pro.offerHighlight")
        }
        application.open(destination, options: [:]) { completionHandler($0) }
    }
}
