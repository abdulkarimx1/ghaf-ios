import Foundation
import AppIntents
import CoreLocation
import GhafCore

/// Receives Apple Pay purchases from the Shortcuts "Transaction" (Wallet) automation. The bank's
/// message for the same purchase is then recognised as a duplicate, not a second purchase.
struct LogWalletTransactionIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Capture Apple Pay"
    static var description = IntentDescription("Add an Apple Pay purchase to Ghaf from the Wallet transaction automation.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Wallet transaction", description: "The transaction passed by the Wallet automation.", inputConnectionBehavior: .connectToPreviousIntentResult)
    var walletTransaction: String?

    // Keep these optional inputs so shortcuts created with the older field mapping still work.
    @Parameter(title: "Amount", description: "Optional legacy Wallet amount.")
    var amount: String?

    @Parameter(title: "Merchant", description: "Optional legacy Wallet merchant.")
    var merchant: String?

    @Parameter(title: "Card", description: "The Wallet Card or Pass name, used to pick the account.")
    var card: String?

    @Parameter(title: "Location", description: "Optional: Current Location, so Ghaf can pin where you paid.")
    var location: CLPlacemark?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let details = WalletTransactionTextParser.parse(walletTransaction ?? "")
        let cleanAmount = amount?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? details.amount
        let cleanMerchant = MerchantName.clean(merchant?.nilIfEmpty ?? details.merchant ?? "")
        let cleanCard = card?.nilIfEmpty ?? details.card
        guard let cleanAmount, !cleanAmount.isEmpty,
              !cleanMerchant.isEmpty,
              let parsedAmount = GhafVoiceTransactionParser.parse(cleanAmount, languageCode: "en", baseCurrency: "AED").first?.amount,
              parsedAmount > 0 else {
            return .result(value: "Ghaf got no transaction details")
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
                sender: cleanCard,
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum WalletTransactionTextParser {
    struct Details {
        var amount: String?
        var merchant: String?
        var card: String?
    }

    static func parse(_ input: String) -> Details {
        let labels = ["amount": "amount", "merchant": "merchant", "card or pass": "card", "card/pass": "card", "card": "card", "name": "merchant"]
        var values: [String: String] = [:]
        if let data = input.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return Details(amount: object["Amount"] ?? object["amount"],
                           merchant: object["Merchant"] ?? object["merchant"],
                           card: object["Card or Pass"] ?? object["card"])
        }
        for line in input.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "|;"))) {
            guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else { continue }
            let label = line[..<separator].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'{}"))).lowercased()
            guard let key = labels[label] else { continue }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            if !value.isEmpty { values[key] = value }
        }
        return Details(amount: values["amount"], merchant: values["merchant"], card: values["card"])
    }
}
