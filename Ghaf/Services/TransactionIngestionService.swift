import Foundation
import CryptoKit
import SwiftData
import GhafCore

struct TransactionIngestionResult {

    enum Status {
        case saved
        case needsReview
        case duplicate
        case ignored
    }

    let status: Status

    let confirmation: String
}

@MainActor
final class TransactionIngestionService {

    private let context: ModelContext

    private let parser: BankMessageParser

    init(
        context: ModelContext,
        parser: BankMessageParser = BankMessageParser()
    ) {
        self.context = context
        self.parser = parser
    }

    func ingest(
        messageText: String,
        sender: String? = nil
    ) throws -> TransactionIngestionResult {

        let message = messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !message.isEmpty else {

            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "Empty message. Nothing saved."
            )
        }

        // Parse before storing anything.
        guard let parsed = parser.parse(
            message,
            sender: sender,
            referenceDate: Date()
        ) else {

            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "No transaction detected."
            )
        }

        // Generate a stable fingerprint from the message.
        let fingerprint = makeFingerprint(message)

        // Check for an existing transaction.
        let descriptor = FetchDescriptor<GhafTransaction>(
            predicate: #Predicate {
                $0.fingerprint == fingerprint
            }
        )

        if try !context.fetch(descriptor).isEmpty {

            return TransactionIngestionResult(
                status: .duplicate,
                confirmation: "Transaction already recorded."
            )
        }

        // Categorize the parsed transaction.
        let category = try MerchantCategorizer.category(
            for: parsed.merchant,
            direction: parsed.direction,
            context: context
        )

        // Determine whether the user should review it.
        let needsReview = parser.shouldSendToReview(parsed) ||
            (parsed.merchant != nil && category == "Other")

        let isReversal = message.range(
            of: "reversal",
            options: [.caseInsensitive]
        ) != nil

        let transaction = GhafTransaction(
            fingerprint: fingerprint,
            parsed: parsed,
            category: category,
            needsReview: needsReview,
            isReversal: isReversal
        )

        context.insert(transaction)

        // Explicit persistence.
        try context.save()

        let amount = NSDecimalNumber(
            decimal: parsed.amount
        ).stringValue

        if needsReview {

            return TransactionIngestionResult(
                status: .needsReview,
                confirmation: "Transaction received. Needs review."
            )
        }

        return TransactionIngestionResult(
            status: .saved,
            confirmation: "Saved \(amount) \(parsed.currency)."
        )
    }

    private func makeFingerprint(
        _ message: String
    ) -> String {

        let normalized = message
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        let data = Data(normalized.utf8)

        let digest = SHA256.hash(data: data)

        return digest.map {
            String(format: "%02x", $0)
        }.joined()
    }
}
