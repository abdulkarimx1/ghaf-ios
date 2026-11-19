#if DEBUG
import Foundation
import SwiftData

@MainActor
enum GhafAutomationIntentHarness {
    static func assertBehavior(in context: ModelContext) throws {
        let defaults = UserDefaults(suiteName: "GhafAutomationIntentHarness")!
        defaults.removePersistentDomain(forName: "GhafAutomationIntentHarness")
        defer { defaults.removePersistentDomain(forName: "GhafAutomationIntentHarness") }

        let before = try context.fetchCount(FetchDescriptor<GhafTransaction>())
        let chosen = ["Mashreq"]
        assert(GhafAutomationCapturePolicy.shouldSkip(bankName: "Mashreq", chosenBanks: chosen, captureEnabled: false))
        GhafAutomationCapturePolicy.recordSkip(for: "Mashreq", defaults: defaults)
        assert(GhafAutomationCapturePolicy.skippedCount(for: "Mashreq", defaults: defaults) == 1)
        let afterSkip = try context.fetchCount(FetchDescriptor<GhafTransaction>())
        assert(afterSkip == before)

        let testMessage = "GHAF TEST"
        assert(testMessage.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "GHAF TEST")
        let afterTest = try context.fetchCount(FetchDescriptor<GhafTransaction>())
        assert(afterTest == before)

        let message = "Purchase of AED 2.00 was made with Card ending XX000 at SAMPLE MERCHANT, TEST AREA. Available Balance: AED 1.35"
        let ingestion = TransactionIngestionService(context: context)
        _ = try ingestion.ingest(messageText: message)
        _ = try ingestion.ingest(messageText: message)
        let afterDuplicate = try context.fetchCount(FetchDescriptor<GhafTransaction>())
        assert(afterDuplicate == before + 1)
    }
}
#endif
