import Foundation
import AppIntents
import CoreLocation
import GhafCore

/// Receives Apple Pay purchases from the Shortcuts "Transaction" (Wallet) automation. The bank's
/// message for the same purchase is then recognised as a duplicate, not a second purchase.
struct LogWalletTransactionIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Add Apple Pay purchase"
    static var description = IntentDescription("Add an Apple Pay purchase to Ghaf from the Wallet transaction automation.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", description: "The Wallet Amount, for example AED 25.00.")
    var amount: String

    @Parameter(title: "Merchant", description: "The Wallet Merchant name.")
    var merchant: String

    @Parameter(title: "Card", description: "The Wallet Card or Pass name, used to pick the account.")
    var card: String?

    @Parameter(title: "Location", description: "Optional: Current Location, so Ghaf can pin where you paid.")
    var location: CLPlacemark?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let cleanAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMerchant = MerchantName.clean(merchant)
        guard !cleanAmount.isEmpty, !cleanMerchant.isEmpty else {
            return .result(value: "Missing amount or merchant. Nothing saved.")
        }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.lastRunKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: GhafAutomationStatus.walletRunKey)
        GhafAutomationStatus.recordRun(source: .wallet)
        // Rates for a purchase abroad; skipped when the cached ones are fresh, and never blocks long.
        await GhafExchangeRates.prepareForIngestion()
        let result = try await MainActor.run {
            let context = try GhafPersistence.shared().mainContext
            // Phrased like a card message so the same parser and validation apply.
            return try TransactionIngestionService(context: context).ingest(
                messageText: "Purchase of \(cleanAmount) with your card at \(cleanMerchant).",
                sender: card,
                fromWallet: true
            )
        }
        if let spot = location?.location, let id = result.transactionID {
            await GhafPlaces.rememberPurchaseSpot(spot, merchant: cleanMerchant, transactionID: id)
        }
        if let id = result.transactionID { try? await GhafWidgetSync.showPurchase(transactionID: id) }
        return .result(value: result.confirmation)
    }
}
