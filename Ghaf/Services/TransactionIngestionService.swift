import Foundation
import CryptoKit
import SwiftData
import UserNotifications
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
    /// The record written, when one was (saved or sent to review).
    var transactionID: UUID? = nil
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

    /// `fromWallet` marks input from the Wallet transaction automation, so the bank's own message
    /// for the same purchase is recognised as a duplicate instead of a second purchase.
    func ingest(
        messageText: String,
        sender: String? = nil,
        fromWallet: Bool = false
    ) throws -> TransactionIngestionResult {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "Empty message. Nothing saved."
            )
        }

        guard let rawParsed = parser.parse(
            message,
            sender: sender,
            referenceDate: .now
        ) else {
            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "No transaction detected."
            )
        }

        let existing = try context.fetch(FetchDescriptor<GhafTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        var knownKeys = Set<String>()
        let knownMerchants = existing.prefix(500).compactMap(\.merchant).filter { knownKeys.insert(MerchantName.key($0)).inserted }
        let merchant = rawParsed.merchant.map { MerchantName.expand(MerchantName.clean($0), known: knownMerchants) }

        // An authorization hold is not money that has moved; the posted message records it.
        if rawParsed.kind == .pending {
            return TransactionIngestionResult(
                status: .ignored,
                confirmation: "Pending authorization. Ghaf records it once the bank posts it."
            )
        }

        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        let activeBankAccounts = accounts.filter {
            !$0.isArchived && $0.type.isBankAccount
        }
        let matchedAccount = GhafAccountBalanceCalculator.matchAccount(
            bank: rawParsed.bank,
            sender: sender,
            accounts: accounts
        )
        // A purchase abroad ("TRY 597.60") is recorded in the account's currency at the last known market
        // rate, keeping the original amount. Without any rate it stays in its own currency, in review.
        let targetCurrency = (matchedAccount ?? (activeBankAccounts.count == 1 ? activeBankAccounts.first : nil))?.currency
            ?? (try? GhafPersistence.settings(in: context).currency) ?? rawParsed.currency
        var parsed = ParsedTransaction(amount: rawParsed.amount, currency: rawParsed.currency, merchant: merchant,
                                       date: rawParsed.date, direction: rawParsed.direction, confidence: rawParsed.confidence,
                                       bank: rawParsed.bank, kind: rawParsed.kind)
        var fx: (rate: Decimal, date: Date)?
        if rawParsed.currency != targetCurrency, let rates = GhafExchangeRates.cached,
           let converted = rates.convert(rawParsed.amount, from: rawParsed.currency, to: targetCurrency),
           let rate = rates.rate(from: rawParsed.currency, to: targetCurrency) {
            parsed = ParsedTransaction(amount: converted, currency: targetCurrency, merchant: merchant,
                                       date: rawParsed.date, direction: rawParsed.direction, confidence: rawParsed.confidence,
                                       bank: rawParsed.bank, kind: rawParsed.kind)
            fx = (rate, rates.updated)
        }

        // A Wallet run carries no reference number, so the minute keeps two identical purchases apart
        // while a repeated run of the same automation is still caught.
        let fingerprint = fromWallet
            ? "wallet-" + makeFingerprint(message + Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).dropLast(3))
            : makeFingerprint(message)
        let descriptor = FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        if try !context.fetch(descriptor).isEmpty {
            return TransactionIngestionResult(
                status: .duplicate,
                confirmation: "Transaction already recorded."
            )
        }

        if let existing = try samePurchaseFromOtherSource(parsed, fromWallet: fromWallet) {
            // Keep one record and fill in whatever the first source was missing.
            if existing.merchant == nil { existing.merchant = parsed.merchant }
            if existing.bank == nil { existing.bank = parsed.bank }
            try context.save()
            return TransactionIngestionResult(
                status: .duplicate,
                confirmation: fromWallet ? "Already recorded from the bank message." : "Already recorded from Apple Wallet."
            )
        }

        let isReversal = parsed.kind == .refund || parsed.kind == .reversal
        // A refund offsets its original purchase, so it takes that purchase's category and account.
        let original = isReversal ? try originalPurchase(for: parsed, direction: parsed.direction == .credit ? "debit" : "credit") : nil

        // The message's own account evidence beats the amount-based guess at the original.
        let resolvedAccount = matchedAccount
            ?? original?.accountID.flatMap { id in accounts.first { $0.id == id } }
            ?? (activeBankAccounts.count == 1 ? activeBankAccounts.first : nil)

        let suggestion = MerchantCategorizer.suggestion(for: parsed.merchant, amount: parsed.amount, date: parsed.date,
                                                        direction: isReversal && original == nil ? .debit : parsed.direction, context: context)
        let category = try original?.category ?? MerchantCategorizer.category(
            for: parsed.merchant,
            direction: isReversal ? .debit : parsed.direction,
            amount: parsed.amount,
            date: parsed.date,
            context: context
        )

        // Never silently leave a bank notification unassigned. This is
        // especially important when the notification body omits the bank name.
        let accountNeedsReview = resolvedAccount == nil
        let needsReview = parser.shouldSendToReview(parsed)
            || (parsed.merchant != nil && category == "Other")
            || accountNeedsReview
            || parsed.currency != targetCurrency
            || (isReversal && original == nil)
            // A guess from the learned model is shown, but stays in review until it is confident.
            || (original == nil && suggestion?.source == .model && (suggestion?.confidence ?? 0) < 0.8)

        let transaction = GhafTransaction(
            fingerprint: fingerprint,
            parsed: parsed,
            category: category,
            needsReview: needsReview,
            isReversal: isReversal,
            accountID: resolvedAccount?.id
        )
        if let fx {
            transaction.originalAmount = rawParsed.amount
            transaction.originalCurrency = rawParsed.currency
            transaction.exchangeRate = fx.rate
            transaction.exchangeRateDate = fx.date
        }
        transaction.subcategory = original != nil ? original?.subcategory : suggestion?.category == category && suggestion?.isNewSubcategory == false
            ? suggestion?.subcategory : nil

        let paidSubscription = parsed.direction == .debit && !isReversal ? try subscriptionPaid(by: parsed) : nil
        if parsed.direction == .debit && !isReversal && paidSubscription == nil {
            _ = try addSubscriptionIfRecurring(parsed, accountID: resolvedAccount?.id)
        }

        // The bank charge is recorded once, here. The subscription stays on its due date until the
        // user confirms the deduction in Subscriptions; it never deducts money itself.
        if let paidSubscription, paidSubscription.accountID == nil {
            paidSubscription.accountID = resolvedAccount?.id
        }

        let unusual = parsed.direction == .debit && !isReversal && paidSubscription == nil
            ? try unusualCharge(parsed) : nil

        context.insert(transaction)
        try context.save()
        // One notification per transaction: the unusual-charge note when it applies, else what was added.
        if let unusual, let merchant = parsed.merchant {
            notifyUnusual(merchant: merchant, parsed: parsed, typical: unusual.typical)
        } else {
            let language = (try? GhafPersistence.settings(in: context).languageCode) ?? "en"
            GhafDigestNotifications.transactionAdded(transaction, needsReview: needsReview, languageCode: language)
        }
        GhafDigestNotifications.reschedule(context: context)
        GhafWidgetSync.refresh(context: context)
        // The Live Activity is started by the calling LiveActivityIntent, which iOS lets run in the background.

        let amountFormatter = NumberFormatter()
        amountFormatter.locale = Locale(identifier: "en_US_POSIX")
        amountFormatter.minimumFractionDigits = 2
        amountFormatter.maximumFractionDigits = 2
        amountFormatter.numberStyle = .decimal
        let amount = amountFormatter.string(from: NSDecimalNumber(decimal: parsed.amount)) ?? NSDecimalNumber(decimal: parsed.amount).stringValue
        let savedName = parsed.merchant ?? category
        if needsReview {
            return TransactionIngestionResult(
                status: .needsReview,
                confirmation: "Saved — needs review: \(savedName) · \(parsed.currency) \(amount)",
                transactionID: transaction.id
            )
        }

        return TransactionIngestionResult(
            status: .saved,
            confirmation: "Saved: \(savedName) · \(parsed.currency) \(amount)",
            transactionID: transaction.id
        )
    }

    /// The active subscription this debit pays, if it is due around the charge date.
    private func subscriptionPaid(by parsed: ParsedTransaction) throws -> GhafSubscription? {
        let currency = parsed.currency
        let active = try context.fetch(FetchDescriptor<GhafSubscription>(
            predicate: #Predicate { $0.isActive && $0.currency == currency }
        ))
        for item in active {
            let tolerance = item.cycle == .weekly ? 2 : 5
            // A higher charge is still this payment; the new price waits for the user's OK in Subscriptions.
            if let raised = SubscriptionDetector.raisedPrice(
                merchant: parsed.merchant, amount: parsed.amount, date: parsed.date,
                subscriptionName: item.name, subscriptionAmount: item.amount, dueDate: item.nextPaymentDate,
                toleranceDays: tolerance) {
                item.proposedAmount = raised
                return item
            }
            if SubscriptionDetector.isPayment(
                merchant: parsed.merchant, amount: parsed.amount, date: parsed.date,
                subscriptionName: item.name, subscriptionAmount: item.amount, dueDate: item.nextPaymentDate,
                toleranceDays: tolerance) {
                return item
            }
        }
        return nil
    }

    /// Suggests a subscription when this debit looks recurring and the merchant is not tracked yet.
    /// It stays inactive, with no reminders, until the user confirms it.
    private func addSubscriptionIfRecurring(_ parsed: ParsedTransaction, accountID: UUID?) throws -> GhafSubscription? {
        guard let merchant = parsed.merchant else { return nil }
        let key = SubscriptionDetector.normalize(merchant)

        let existing = try context.fetch(FetchDescriptor<GhafSubscription>())
        if existing.contains(where: { SubscriptionDetector.normalize($0.name) == key }) { return nil }

        let debits = try context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.direction == "debit" && $0.merchant != nil }
        ))
        let history = debits.map {
            SubscriptionDetector.PastCharge(merchant: $0.merchant ?? "", amount: $0.amount, date: $0.date)
        }

        guard let cycle = SubscriptionDetector.detect(
            merchant: merchant, amount: parsed.amount, date: parsed.date, history: history
        ), let billing = GhafBillingCycle(rawValue: cycle.rawValue) else { return nil }

        let subscription = GhafSubscription(
            name: merchant,
            amount: parsed.amount,
            currency: parsed.currency,
            billingCycle: billing,
            nextPaymentDate: billing.nextDate(after: parsed.date),
            accountID: accountID,
            isActive: false,
            notes: "Auto-detected from a bank message"
        )
        subscription.needsConfirmation = true
        context.insert(subscription)
        return subscription
    }

    private func samePurchaseFromOtherSource(_ parsed: ParsedTransaction, fromWallet: Bool) throws -> GhafTransaction? {
        let since = Date.now.addingTimeInterval(-CrossSourceDuplicate.window)
        let amount = parsed.amount
        let recent = try context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.createdAt >= since && $0.amount == amount }
        ))
        let incoming = CrossSourceDuplicate.Record(
            amount: parsed.amount, currency: parsed.currency, isDebit: parsed.direction == .debit,
            merchant: parsed.merchant, arrivedAt: .now, isWallet: fromWallet
        )
        return recent.first { item in
            CrossSourceDuplicate.isSamePurchase(incoming, .init(
                amount: item.amount, currency: item.currency, isDebit: item.direction == "debit",
                merchant: item.merchant, arrivedAt: item.createdAt, isWallet: item.fingerprint.hasPrefix("wallet-")
            ))
        }
    }

    /// Compared with earlier charges at the same merchant, in the same currency.
    private func unusualCharge(_ parsed: ParsedTransaction) throws -> SpendingInsights.Unusual? {
        guard let merchant = parsed.merchant else { return nil }
        let currency = parsed.currency
        let key = SubscriptionDetector.normalize(merchant)
        let earlier = try context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { $0.direction == "debit" && !$0.isReversal && $0.currency == currency && $0.merchant != nil }
        )).filter { SubscriptionDetector.normalize($0.merchant ?? "") == key }.map(\.amount)
        return SpendingInsights.unusual(amount: parsed.amount, previous: earlier)
    }

    /// A heads-up only; nothing about the transaction changes. Silent when notifications are off.
    private func notifyUnusual(merchant: String, parsed: ParsedTransaction, typical: Decimal) {
        let language = (try? GhafPersistence.settings(in: context).languageCode) ?? "en"
        let amount = GhafFormat.money(parsed.amount, currency: parsed.currency, languageCode: language)
        let usual = GhafFormat.money(typical, currency: parsed.currency, languageCode: language)
        let content = UNMutableNotificationContent()
        content.title = language == "ar" ? "عملية أعلى من المعتاد" : "Higher than usual"
        content.body = language == "ar"
            ? "\(amount) عند \(merchant). عادةً تدفع هناك حوالي \(usual)."
            : "\(amount) at \(merchant). You usually spend about \(usual) there."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ghaf.unusual.\(UUID().uuidString)",
                                                                     content: content, trigger: nil))
    }

    /// Most recent transaction the reversal offsets: same amount, currency and merchant within 90 days.
    private func originalPurchase(for parsed: ParsedTransaction, direction: String) throws -> GhafTransaction? {
        let amount = parsed.amount, currency = parsed.currency, end = parsed.date
        let start = end.addingTimeInterval(-90 * 86_400)
        var descriptor = FetchDescriptor<GhafTransaction>(
            predicate: #Predicate {
                $0.direction == direction && !$0.isReversal && $0.amount == amount
                    && $0.currency == currency && $0.date >= start && $0.date <= end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let key = parsed.merchant.map(SubscriptionDetector.normalize)
        return try context.fetch(descriptor).first { candidate in
            guard candidate.isSpendingOrIncome else { return false }
            // Without a merchant on both sides the link is a guess; leave it for review.
            guard let key, let merchant = candidate.merchant else { return false }
            return SubscriptionDetector.normalize(merchant) == key
        }
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
