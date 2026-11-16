import Foundation
import AppIntents

/// Receives Apple Pay purchases from the Shortcuts "Transaction" (Wallet) automation. The bank's
/// message for the same purchase is then recognised as a duplicate, not a second purchase.
struct LogWalletTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Apple Pay purchase"
    static var description = IntentDescription("Add an Apple Pay purchase to Ghaf from the Wallet transaction automation.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", description: "The Wallet Amount, for example AED 25.00.")
    var amount: String

    @Parameter(title: "Merchant", description: "The Wallet Merchant name.")
    var merchant: String

    @Parameter(title: "Card", description: "The Wallet Card or Pass name, used to pick the account.")
    var card: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let cleanAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAmount.isEmpty, !cleanMerchant.isEmpty else {
            return .result(value: "Missing amount or merchant. Nothing saved.")
        }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.lastRunKey)
        let confirmation = try await MainActor.run {
            let context = try GhafPersistence.shared().mainContext
            // Phrased like a card message so the same parser and validation apply.
            return try TransactionIngestionService(context: context).ingest(
                messageText: "Purchase of \(cleanAmount) at \(cleanMerchant).",
                sender: card,
                fromWallet: true
            ).confirmation
        }
        return .result(value: confirmation)
    }
}
