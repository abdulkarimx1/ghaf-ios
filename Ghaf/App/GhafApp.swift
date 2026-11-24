import SwiftUI
import SwiftData
import UIKit
import OSLog

@main
struct GhafApp: App {
    private static let proofLogger = Logger(subsystem: "com.ghaf.app", category: "BackupProof")
    @UIApplicationDelegateAdaptor(GhafAppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    @AppStorage(GhafFormat.hideBalancesKey) private var hideBalances = false
    @State private var handledUnreadUITestHook = false
    @State private var settingsAuditStatus: String?

    init() {
#if DEBUG
        GhafLocalization.assertArabicDays()
#endif
        // Native bounce stays on: it is part of iOS's fluid feel.
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        UIScrollView.appearance().showsVerticalScrollIndicator = false

        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-GhafSettingsPersistenceAudit") {
                modelContainer = try GhafPersistence.makeSettingsAuditContainer()
            } else if GhafScreenshotFixture.enabled {
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
#if DEBUG
        GhafSounds.shared.playSimulatorCheckIfRequested()
#endif
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
                .onAppear {
#if DEBUG
                    runUnreadUITestHookIfRequested()
                    if ProcessInfo.processInfo.arguments.contains("-GhafActivityLifecycleProof") {
                        Task { await GhafWidgetSync.runLifecycleProof() }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-GhafActivityVisualProof") {
                        Task { await GhafWidgetSync.runVisualProof() }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-GhafBackupArabicNameProof") {
                        do {
                            let result = try GhafBackupService.debugArabicNameRoundTripProof()
                            Self.proofLogger.notice("GHAF_BACKUP_ARABIC_NAME_PROOF \(result, privacy: .public)")
                        }
                        catch { Self.proofLogger.error("GHAF_BACKUP_ARABIC_NAME_PROOF failed") }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-GhafSettingsPersistenceAudit"),
                       let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-GhafSettingsPersistenceAuditPhase"),
                       ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                        do { settingsAuditStatus = try GhafSettingsPersistenceAudit.run(ProcessInfo.processInfo.arguments[index + 1], context: modelContainer.mainContext) }
                        catch { settingsAuditStatus = "Settings persistence audit failed: \(error.localizedDescription)" }
                    }
#endif
                }
                .overlay(alignment: .top) {
                    if let settingsAuditStatus {
                        Text(settingsAuditStatus)
                            .font(.caption)
                            .padding(8)
                            .accessibilityIdentifier("ghaf.settings-audit.status")
                    }
                }
        }
        .modelContainer(modelContainer)
    }

#if DEBUG
    @MainActor
    private func runUnreadUITestHookIfRequested() {
        guard !handledUnreadUITestHook else { return }
        handledUnreadUITestHook = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-GhafUITestInjectUnread") {
            let message = "Mashreq: AED 8.00 was debited from card ending 1234 at Session F Test Cafe."
            _ = try? TransactionIngestionService(context: modelContainer.mainContext).ingest(messageText: message, sender: "Mashreq")
        }
        if arguments.contains("-GhafUITestCleanupUnread") {
            let testTransactions = (try? modelContainer.mainContext.fetch(FetchDescriptor<GhafTransaction>())) ?? []
            testTransactions.filter { $0.merchant == "Session F Test Cafe" || $0.rawMerchant == "Session F Test Cafe" }
                .forEach(modelContainer.mainContext.delete)
            try? modelContainer.mainContext.save()
        }
    }
#endif
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
