import Foundation
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
        notificationTitle: String? = nil,
        sender: String? = nil
    ) throws -> TransactionIngestionResult {
        let message = [notificationTitle, messageText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        let duplicateWindowStart = Date.now.addingTimeInterval(-180)
        let recentDescriptor = FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.createdAt >= duplicateWindowStart }
        )
        let recentTransactions = try context.fetch(recentDescriptor)
        let normalizedMerchant = normalizeMerchant(parsed.merchant)
        let isRecentDuplicate = recentTransactions.contains { existing in
            guard existing.amount == parsed.amount,
                  existing.currency == parsed.currency,
                  existing.direction == parsed.direction.rawValue,
                  normalizeMerchant(existing.merchant) == normalizedMerchant else {
                return false
            }

            // When both sources identify a bank, require the same bank.
            return existing.bank == nil || parsed.bank == nil || existing.bank == parsed.bank
        }
        if isRecentDuplicate {
            return TransactionIngestionResult(
                status: .duplicate,
                confirmation: "Matching transaction already received within the last 3 minutes."
            )
        }

        // Fingerprints remain unique. Duplicate protection is based on parsed
        // transaction details and a short creation-time window, not permanent
        // equality of the original notification text.
        let fingerprint = UUID().uuidString

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
            direction: parsed.direction,
            context: context
        )

        let accountNeedsReview = !activeBankAccounts.isEmpty
            && (parsed.bank != nil || sender != nil)
            && resolvedAccount == nil
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

    private func normalizeMerchant(_ merchant: String?) -> String? {
        merchant?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
