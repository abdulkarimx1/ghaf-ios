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

        let confirmation = try await MainActor.run {

            let container = try GhafPersistence.makeContainer()

            let context = ModelContext(container)

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
