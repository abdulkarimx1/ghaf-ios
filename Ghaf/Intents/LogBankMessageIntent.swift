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
}
