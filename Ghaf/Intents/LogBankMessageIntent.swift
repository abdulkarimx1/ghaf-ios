import Foundation
import AppIntents
import SwiftData

struct LogBankMessageIntent: AppIntent {

    static var title: LocalizedStringResource =
        "Log Bank Message"

    static var description = IntentDescription(
        "Parse and save a bank transaction locally in Ghaf."
    )

    // The action must not open the main application.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Message Text",
        description: "The incoming bank transaction message."
    )
    var messageText: String

    @Parameter(
        title: "Sender / App Name",
        description: "The bank or application name."
    )
    var sender: String?

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
                sender: sender
            )

            return result.confirmation
        }

        return .result(value: confirmation)
    }
}
