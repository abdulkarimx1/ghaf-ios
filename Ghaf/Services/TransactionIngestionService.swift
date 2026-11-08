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
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "Empty message. Nothing saved."
            )
        }

        guard let parsed = parser.parse(
            message,
            sender: sender,
            referenceDate: .now
        ) else {
            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "No transaction detected."
            )
        }

        let fingerprint = makeFingerprint(message)
        let descriptor = FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        if try !context.fetch(descriptor).isEmpty {
            return TransactionIngestionResult(
                status: .duplicate,
                confirmation: "Transaction already recorded."
            )
        }

        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        let activeBankAccounts = accounts.filter {
            !$0.isArchived && $0.type.isBankAccount
        }
        let matchedAccount = GhafAccountBalanceCalculator.matchAccount(
            bank: parsed.bank,
            sender: sender,
            accounts: accounts
        )
        let resolvedAccount = matchedAccount
            ?? (activeBankAccounts.count == 1 ? activeBankAccounts.first : nil)

        let category = try MerchantCategorizer.category(
            for: parsed.merchant,
            direction: parsed.direction.rawValue,
            context: context
        )

        // Never silently leave a bank notification unassigned. This is
        // especially important when the notification body omits the bank name.
        let accountNeedsReview = resolvedAccount == nil
        let needsReview = parser.shouldSendToReview(parsed)
            || (parsed.merchant != nil && category == "Other")
            || accountNeedsReview

        let isReversal = message.range(
            of: "reversal|reversed|refund",
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        let transaction = GhafTransaction(
            fingerprint: fingerprint,
            parsed: parsed,
            category: category,
            needsReview: needsReview,
            isReversal: isReversal,
            accountID: resolvedAccount?.id
        )

        context.insert(transaction)
        try context.save()

        let amount = NSDecimalNumber(decimal: parsed.amount).stringValue
        if needsReview {
            return TransactionIngestionResult(
                status: .needsReview,
                confirmation: "Transaction received. Review its category or account."
            )
        }

        return TransactionIngestionResult(
            status: .saved,
            confirmation: "Saved \(amount) \(parsed.currency)."
        )
    }

    private func makeFingerprint(_ message: String) -> String {
        let normalized = message
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
