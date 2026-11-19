#if DEBUG
import Foundation
import SwiftData
import GhafCore

@MainActor
enum GhafScreenshotFixture {
    private static let arguments = ProcessInfo.processInfo.arguments
    static var enabled: Bool { value("GhafFixture") == "1" }
    static var autoSelect: Bool { enabled && value("GhafAutoSelect") == "1" }
    static var theme: String { value("GhafTheme") ?? "Graphite" }
    static var appearance: String { value("GhafAppearance") ?? "Light" }
    static var language: String { value("GhafLanguage") ?? "en" }
    static var tab: String { value("GhafTab") ?? (["ai-typing", "ai-conversation"].contains(value("GhafScreen") ?? "") ? "ai" : "home") }
    static var selection: String? { value("GhafSelection") }
    static var period: String? { value("GhafPeriod") }
    static var screen: String? {
        ["budget", "pro-popup", "pro-sheet"].contains(value("GhafScreen") ?? "") ? "insights" : value("GhafScreen")
    }
    static var destination: String? { value("GhafScreen") }
    static var automationExpanded: Bool { value("GhafAutomationExpanded") == "bank" }
    static var automationButtonProof: Bool { value("GhafAutomationButtonProof") == "1" }
    static var automationState: String { ["none", "waiting", "working"].contains(value("GhafAutomationState") ?? "none") ? (value("GhafAutomationState") ?? "none") : "none" }

    static func applyAutomation() {
        let defaults = UserDefaults.standard
        let banks = automationState == "none" ? [] : ["Mashreq", "iVestor", "ruya"]
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
        defaults.set(Date.now.addingTimeInterval(-2 * 60 * 60).timeIntervalSince1970, forKey: "ghaf.automation.lastSeen.Mashreq")
        defaults.removeObject(forKey: "ghaf.automation.lastSeen.ruya")
        let run = automationState == "working" ? Date.now.timeIntervalSince1970 : 0
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
        let configuration = ModelConfiguration("GhafScreenshotFixture", schema: schema,
                                                isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        seed(container.mainContext)
        if arguments.contains("-GhafAutomationProof") { try GhafAutomationIntentHarness.assertBehavior(in: container.mainContext) }
        return container
    }

    private static func seed(_ context: ModelContext) {
        let settings = GhafSettings(languageCode: language, currency: "AED", monthlyIncome: 12000, themeName: theme,
                                    appearanceMode: appearance, hasCompletedOnboarding: true)
        context.insert(settings)
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
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
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
                                            nextPaymentDate: Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now,
                                            accountID: mashreq.id))
        }
        try? context.save()
    }
}
#endif
