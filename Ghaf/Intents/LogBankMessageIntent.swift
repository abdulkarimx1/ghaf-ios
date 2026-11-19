import Foundation
import AppIntents
import CoreLocation
import SwiftData
import GhafCore

struct LogBankMessageIntent: AppIntent {

    static var title: LocalizedStringResource = "Log bank message"

    static var description = IntentDescription(
        "Add a bank transaction to Ghaf from the incoming notification text."
    )

    // The action must not open the main application.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Message text",
        description: "محتوى إشعار أو رسالة العملية البنكية الواردة."
    )
    var messageText: String

    @Parameter(title: "Sender", description: "Optional sender name from the incoming bank message.")
    var sender: String?

    @Parameter(title: "Location", description: "Optional: Current Location, so Ghaf can pin where you paid.")
    var location: CLPlacemark?

    func perform() async throws
        -> some IntentResult & ReturnsValue<String> {

        let isTest = messageText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "GHAF TEST"
        UserDefaults.standard.set(isTest, forKey: GhafAutomationStatus.lastRunWasTestKey)
        if isTest {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.testRunKey)
            return .result(value: "Ghaf is connected ✓")
        }
#if DEBUG
        GhafAutomationCapturePolicy.assertPolicy()
#endif

        let bankName = try await MainActor.run { () -> String? in
            let context = try GhafPersistence.shared().mainContext
            let parsed = BankMessageParser().parse(messageText, referenceDate: .now)
            guard let parsed else { return nil }
            let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
            let account = GhafAccountBalanceCalculator.matchAccount(bank: parsed.bank, sender: sender, accounts: accounts)
            return GhafBankSupportDirectory.contact(for: [parsed.bank, account?.institution, account?.name])?.name
        }
        let defaults = UserDefaults.standard
        defaults.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.lastRunKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.messageRunKey)
        GhafAutomationStatus.recordRun(source: .message)
        if let bankName {
            defaults.set(Date.now.timeIntervalSince1970, forKey: "ghaf.automation.lastSeen.\(bankName)")
            let chosenBanks = defaults.stringArray(forKey: GhafAutomationBanks.key) ?? []
            if GhafAutomationCapturePolicy.shouldSkip(
                bankName: bankName,
                chosenBanks: chosenBanks,
                captureEnabled: GhafAutomationCapturePolicy.captureIsEnabled(for: bankName, defaults: defaults)
            ) {
                GhafAutomationCapturePolicy.recordSkip(for: bankName, defaults: defaults)
                return .result(value: "Skipped — capture for \(bankName) is off in Ghaf")
            }
        }
        // Rates for a purchase abroad; skipped when the cached ones are fresh, and never blocks long.
        await GhafExchangeRates.prepareForIngestion()
        let confirmation = try await MainActor.run {

            let container = try GhafPersistence.shared()

            let context = container.mainContext

            let service = TransactionIngestionService(
                context: context
            )

            let result = try service.ingest(
                messageText: messageText,
                sender: sender
            )

            return result
        }
        if let spot = location?.location, let id = confirmation.transactionID {
            let merchant = try await MainActor.run {
                let context = try GhafPersistence.shared().mainContext
                return try context.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == id })).first?.merchant
            }
            if let merchant { await GhafPlaces.rememberPurchaseSpot(spot, merchant: merchant, transactionID: id) }
        }

        return .result(value: confirmation.confirmation)
    }
}

/// When an automation last delivered a message to Ghaf (0 = never), so the app knows setup worked.
enum GhafAutomationStatus {
    static let lastRunKey = "ghaf.automation.lastRun"
    /// Per-source runs, so the setup checklist ticks only the step that actually worked.
    static let messageRunKey = "ghaf.automation.lastMessageRun"
    static let walletRunKey = "ghaf.automation.lastWalletRun"
    static let testRunKey = "ghaf.automation.lastTestRun"
    static let messageHistoryKey = "ghaf.automation.messageHistory"
    static let walletHistoryKey = "ghaf.automation.walletHistory"
    static let setupCompletedKey = "ghaf.automation.setupCompleted"
    static let warningDismissedUntilKey = "ghaf.automation.warningDismissedUntil"
    static let lastRunWasTestKey = "ghaf.automation.lastRunWasTest"

    enum Source { case message, wallet }

    static func recordRun(source: Source, at date: Date = .now) {
        let key = switch source {
        case .message: messageHistoryKey
        case .wallet: walletHistoryKey
        }
        var runs = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        runs.append(date.timeIntervalSince1970)
        UserDefaults.standard.set(Array(runs.suffix(20)), forKey: key)
    }
}
