import Foundation
import AppIntents
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

            return result.confirmation
        }

        return .result(value: confirmation)
    }
}

/// When an automation last delivered a message to Ghaf (0 = never), so the app knows setup worked.
enum GhafAutomationStatus {
    static let lastRunKey = "ghaf.automation.lastRun"
}
