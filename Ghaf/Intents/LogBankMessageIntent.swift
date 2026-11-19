import Foundation
import AppIntents
import CoreLocation
import SwiftData

struct LogBankMessageIntent: AppIntent {

    static var title: LocalizedStringResource =
        "أضف عملية من رسالة بنكية"

    static var description = IntentDescription(
        "Add a bank transaction to Ghaf from the incoming notification text."
    )

    // The action must not open the main application.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "نص الرسالة",
        description: "محتوى إشعار أو رسالة العملية البنكية الواردة."
    )
    var messageText: String

    @Parameter(title: "Location", description: "Optional: Current Location, so Ghaf can pin where you paid.")
    var location: CLPlacemark?

    func perform() async throws
        -> some IntentResult & ReturnsValue<String> {

        // Reaching this line proves the user's automation runs; Home hides its setup card from now on.
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.lastRunKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.messageRunKey)
        GhafAutomationStatus.recordRun(source: .message)
        let isTest = messageText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "GHAF TEST"
        UserDefaults.standard.set(isTest, forKey: GhafAutomationStatus.lastRunWasTestKey)
        if isTest {
            return .result(value: "Ghaf is connected ✓")
        }
        // Rates for a purchase abroad; skipped when the cached ones are fresh, and never blocks long.
        await GhafExchangeRates.refreshIfStale()
        let confirmation = try await MainActor.run {

            let container = try GhafPersistence.shared()

            let context = container.mainContext

            let service = TransactionIngestionService(
                context: context
            )

            let result = try service.ingest(
                messageText: messageText,
                sender: nil
            )

            return result
        }
        if let spot = location?.location, let id = confirmation.transactionID {
            let context = try await MainActor.run { try GhafPersistence.shared().mainContext }
            let merchant = await MainActor.run {
                (try? context.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == id })).first?.merchant) ?? nil
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
