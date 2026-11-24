#if DEBUG
import Foundation
import SwiftData
import GhafCore

@MainActor
enum GhafScreenshotFixture {
    private static let arguments = ProcessInfo.processInfo.arguments
    static var snapshotTestingEnabled = false
    static var snapshotScreenOverride: String?
    static var snapshotPeriodOverride: String?
    static var enabled: Bool { snapshotTestingEnabled || value("GhafFixture") == "1" }
    static var launchProof: Bool { enabled && value("GhafLaunchProof") == "1" }
    static var launchNewUser: Bool { launchProof && value("GhafLaunchNewUser") == "1" }
    static var autoSelect: Bool { enabled && value("GhafAutoSelect") == "1" }
    static var theme: String { value("GhafTheme") ?? "Graphite" }
    static var appearance: String { value("GhafAppearance") ?? "Light" }
    static var language: String { value("GhafLanguage") ?? "en" }
    static var tab: String { value("GhafTab") ?? (["ai-typing", "ai-conversation", "ai-subscription-answer"].contains(value("GhafScreen") ?? "") ? "ai" : "home") }
    static var selection: String? { value("GhafSelection") }
    static var period: String? { snapshotPeriodOverride ?? value("GhafPeriod") }
    private static var rawScreen: String? { snapshotScreenOverride ?? value("GhafScreen") }
    static var screen: String? {
        ["budget", "pro-popup", "pro-sheet"].contains(rawScreen ?? "") ? "insights" : rawScreen
    }
    static var destination: String? { rawScreen }
    static var importSheetRoute: Bool { enabled && destination == "importSheet" }
    static var automationExpanded: String { value("GhafAutomationExpanded") ?? "bank" }
    static var automationPage: Int? { value("GhafAutomationPage").flatMap(Int.init) }
    static var automationButtonProof: Bool { value("GhafAutomationButtonProof") == "1" }
    static var automationState: String { ["none", "waiting", "working"].contains(value("GhafAutomationState") ?? "none") ? (value("GhafAutomationState") ?? "none") : "none" }

    static func applyAutomation(state overrideState: String? = nil) {
        let defaults = UserDefaults.standard
        let state = overrideState ?? automationState
        let banks = state == "none" ? [] : ["Mashreq", "iVestor", "ruya"]
        GhafAutomationBanks.save(banks, defaults: defaults)
        for name in ["Mashreq", "iVestor", "ruya"] where !banks.contains(name) {
            defaults.removeObject(forKey: "ghaf.automation.bankEnabled.\(name)")
            defaults.removeObject(forKey: "ghaf.automation.skipped.\(name)")
            defaults.removeObject(forKey: "ghaf.automation.lastSeen.\(name)")
        }
        guard !banks.isEmpty else {
            for key in [GhafAutomationStatus.messageRunKey, GhafAutomationStatus.walletRunKey,
                        GhafAutomationStatus.testRunKey, GhafAutomationStatus.lastRunKey] {
                defaults.removeObject(forKey: key)
            }
            return
        }
        defaults.set(true, forKey: "ghaf.automation.bankEnabled.Mashreq")
        defaults.set(false, forKey: "ghaf.automation.bankEnabled.iVestor")
        defaults.set(3, forKey: "ghaf.automation.skipped.iVestor")
        // Keep the snapshot's reference copy of the latest Mashreq alert (15 hours old).
        defaults.set(GhafClock.now.addingTimeInterval(-15 * 60 * 60).timeIntervalSince1970, forKey: "ghaf.automation.lastSeen.Mashreq")
        defaults.removeObject(forKey: "ghaf.automation.lastSeen.ruya")
        let run = state == "working" ? GhafClock.now.timeIntervalSince1970 : 0
        for key in [GhafAutomationStatus.messageRunKey, GhafAutomationStatus.walletRunKey, GhafAutomationStatus.testRunKey, GhafAutomationStatus.lastRunKey] {
            defaults.set(run, forKey: key)
        }
    }

    private static func value(_ key: String) -> String? {
        guard let index = arguments.firstIndex(of: "-\(key)"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([GhafTransaction.self, GhafSettings.self, GhafAccount.self,
                             MerchantCategoryRule.self, GhafSubscription.self, GhafChat.self, GhafMemory.self])
        // -GhafFixtureOnDisk: keep the fixture in a temp file so a UI test can prove state survives relaunch;
        // -GhafFixtureReset starts that file fresh. Seeded only when empty.
        let onDisk = arguments.contains("-GhafFixtureOnDisk")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GhafFixtureOnDisk.store")
        if onDisk, arguments.contains("-GhafFixtureReset") {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let configuration = onDisk
            ? ModelConfiguration("GhafFixtureOnDisk", schema: schema, url: url, cloudKitDatabase: .none)
            : ModelConfiguration("GhafScreenshotFixture", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if onDisk, (try container.mainContext.fetchCount(FetchDescriptor<GhafSettings>())) > 0 { return container }
        // -GhafRestoreBackup <path>: load a real Ghaf backup instead of the sample data, to prove fixes on real data.
        if let i = arguments.firstIndex(of: "-GhafRestoreBackup"), i + 1 < arguments.count {
            try GhafBackupService.restore(from: URL(fileURLWithPath: arguments[i + 1]), context: container.mainContext)
            if let s = try container.mainContext.fetch(FetchDescriptor<GhafSettings>()).first {
                s.themeName = theme; s.appearanceMode = appearance; s.languageCode = language
            }
        } else if arguments.contains("-GhafStreakUITestFixture") {
            seedStreak(container.mainContext)
        } else {
            seed(container.mainContext)
        }
        if arguments.contains("-GhafAutomationProof") { try GhafAutomationIntentHarness.assertBehavior(in: container.mainContext) }
        return container
    }

    private static func seed(_ context: ModelContext) {
        let settings = GhafSettings(languageCode: language, currency: "AED", monthlyIncome: 12000, themeName: theme,
                                    appearanceMode: appearance, hasCompletedOnboarding: !launchNewUser)
        if !launchNewUser { settings.userName = "Amina" }
        context.insert(settings)
        if launchNewUser { try? context.save(); return }
        let mashreq = GhafAccount(name: "Mashreq Current", institution: "Mashreq", accountType: .current,
                                  currency: "AED", openingBalance: 8500, isPrimary: true, sortOrder: 0)
        let cash = GhafAccount(name: "Cash wallet", accountType: .cash, currency: "AED",
                               openingBalance: 650, sortOrder: 1)
        context.insert(mashreq); context.insert(cash)
        let samples: [(String, Decimal, String, String, Int)] = [
            ("Carrefour", 184.50, "Groceries", "debit", 1), ("Local Cafe", 32, "Dining", "debit", 2),
            ("Fuel Station", 120, "Transport", "debit", 3), ("Noon", 89.99, "Shopping", "debit", 4),
            ("Electricity", 245, "Bills", "debit", 5), ("Salary", 7200, "Income", "credit", 6),
            ("Transfer to Cash", 300, "Transfers", "debit", 7), ("Bakery", 24, "Dining", "debit", 8),
            ("Carrefour", 96.30, "Groceries", "debit", 9), ("Taxi", 46, "Transport", "debit", 10),
            ("Pharmacy", 58, "Health", "debit", 11), ("Streaming", 39.99, "Subscriptions", "debit", 12),
            ("Restaurant", 155, "Dining", "debit", 13), ("Bookshop", 72, "Shopping", "debit", 14),
            ("Water bill", 83, "Bills", "debit", 15), ("Market", 67, "Groceries", "debit", 16),
            ("Bus pass", 100, "Transport", "debit", 17), ("Clinic", 180, "Health", "debit", 18),
            ("Lunch", 45, "Dining", "debit", 19), ("Online store", 210, "Shopping", "debit", 20),
            ("Internet", 299, "Bills", "debit", 21), ("Fruit shop", 38, "Groceries", "debit", 22),
            ("Coffee", 22, "Dining", "debit", 23), ("Fuel Station", 130, "Transport", "debit", 24),
            ("Transfer from Cash", 150, "Transfers", "credit", 25)
        ]
        for (merchant, amount, category, direction, daysAgo) in samples {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: GhafClock.now) ?? GhafClock.now
            let parsed = ParsedTransaction(amount: amount, currency: "AED", merchant: merchant, date: date,
                                           direction: direction == "credit" ? .credit : .debit,
                                           confidence: 1, bank: "Mashreq")
            let transaction = GhafTransaction(fingerprint: "fixture-\(daysAgo)", parsed: parsed,
                                              category: category, needsReview: false, isReversal: false,
                                              accountID: category == "Transfers" ? cash.id : mashreq.id)
            context.insert(transaction)
        }
        for (name, amount, cycle, days) in [("Music", Decimal(21), GhafBillingCycle.monthly, 4),
                                             ("Cloud storage", Decimal(299), .yearly, 12),
                                             ("Weekly news", Decimal(8), .weekly, 2)] {
            context.insert(GhafSubscription(name: name, amount: amount, billingCycle: cycle,
                                            nextPaymentDate: Calendar.current.date(byAdding: .day, value: days, to: GhafClock.now) ?? GhafClock.now,
                                            accountID: mashreq.id))
        }
        try? context.save()
    }

    private static func seedStreak(_ context: ModelContext) {
        let settings = GhafSettings(languageCode: language, currency: "AED", monthlyIncome: 12_000,
                                    themeName: theme, appearanceMode: appearance, hasCompletedOnboarding: true)
        settings.userName = "Amina"
        let account = GhafAccount(name: "Mashreq Current", institution: "Mashreq", accountType: .current,
                                  currency: "AED", openingBalance: 8_500, isPrimary: true, sortOrder: 0)
        context.insert(settings)
        context.insert(account)
        for daysAgo in 1...6 {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: GhafClock.now) ?? GhafClock.now
            let parsed = ParsedTransaction(amount: 10, currency: "AED", merchant: "Streak fixture \(daysAgo)", date: date,
                                           direction: .debit, confidence: 1, bank: "Mashreq")
            context.insert(GhafTransaction(fingerprint: "streak-fixture-\(daysAgo)", parsed: parsed,
                                           category: "Food & Dining", needsReview: false, isReversal: false,
                                           accountID: account.id))
        }
        try? context.save()
    }
}
#endif

#if DEBUG
extension GhafScreenshotFixture {
    static var progressStageFixture: String? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "-GhafAIStage"), args.indices.contains(index + 1) else { return nil }
        let stage = args[index + 1]
        return ["listening", "transcribing", "checking", "adding", "asking", "chart", "draft"].contains(stage) ? stage : nil
    }

    static var attentionMarksFixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "-GhafAttentionMarks"), args.indices.contains(index + 1) else { return false }
        return args[index + 1] == "1"
    }

    static func seedAttentionMarks(in context: ModelContext) {
        let transactions = (try? context.fetch(FetchDescriptor<GhafTransaction>())) ?? []
        let subscriptions = (try? context.fetch(FetchDescriptor<GhafSubscription>())) ?? []
        for index in 1...3 where !transactions.contains(where: { $0.fingerprint == "fixture-attention-review-\(index)" }) {
            let parsed = ParsedTransaction(amount: Decimal(index * 12), currency: "AED", merchant: "Review fixture \(index)", date: GhafClock.now,
                                           direction: .debit, confidence: 0.5, bank: "Mashreq")
            context.insert(GhafTransaction(fingerprint: "fixture-attention-review-\(index)", parsed: parsed,
                                           category: "Other", needsReview: true, isReversal: false))
        }
        for index in 1...3 where !subscriptions.contains(where: { $0.name == "Confirmation fixture \(index)" }) {
            let subscription = GhafSubscription(name: "Confirmation fixture \(index)", amount: Decimal(index * 19),
                                                nextPaymentDate: GhafClock.now, isActive: false)
            subscription.needsConfirmation = true
            context.insert(subscription)
        }
        try? context.save()
    }

    static func configureInbox(context: ModelContext, settings: GhafSettings) {
        guard enabled else { return }
        guard ["inbox-proof", "home-inbox-count"].contains(screen ?? "") else {
            GhafEventNotifications.setFixtureEvents([])
            return
        }
        if (try? context.fetch(FetchDescriptor<GhafTransaction>()).contains(where: { $0.fingerprint == "r3-inbox-fixture" })) != true {
            let parsed = ParsedTransaction(amount: 84.50, currency: settings.currency, merchant: "Local Cafe", date: GhafClock.now,
                                           direction: .debit, confidence: 0.72, bank: "Mashreq")
            context.insert(GhafTransaction(fingerprint: "r3-inbox-fixture", parsed: parsed, category: "Dining",
                                           needsReview: true, isReversal: false, accountID: nil))
            let subscription = GhafSubscription(name: "Cloud storage", amount: 18.99, currency: settings.currency,
                                                billingCycle: .monthly, nextPaymentDate: GhafClock.now, isActive: false)
            subscription.needsConfirmation = true
            context.insert(subscription)
            try? context.save()
        }
        GhafEventNotifications.setFixtureEvents([
            GhafInboxEvent(id: "fixture-budget-80", kind: .budgetThreshold, title: "Dining reached 80% of its budget",
                           message: "Dining spending reached 80% of its monthly budget.", itemID: nil, date: GhafClock.now)
        ])
    }
}
#endif
