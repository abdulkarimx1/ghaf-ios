import Foundation
import OSLog
import SwiftData
import GhafCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Deterministic numbers the assistant may quote. The language model never calculates money itself.
enum GhafFinanceFacts {
    static func summary(
        accounts: [GhafAccount],
        transactions: [GhafTransaction],
        subscriptions: [GhafSubscription],
        now: Date = .now
    ) -> String {
        let calendar = Calendar.current
        var lines: [String] = ["Today is \(now.formatted(date: .complete, time: .omitted))."]

        let open = accounts.filter { !$0.isArchived }
        if open.isEmpty {
            lines.append("The user has no accounts yet.")
        } else {
            lines.append("Accounts (balance each, never add different currencies):")
            for account in open {
                let balance = GhafAccountBalanceCalculator.balance(for: account, transactions: transactions)
                lines.append("- \(account.name): \(fmt(balance)) \(account.currency)")
            }
        }

        func window(_ component: Calendar.Component, offset: Int = 0) -> DateInterval? {
            guard let date = calendar.date(byAdding: component, value: offset, to: now) else { return nil }
            return calendar.dateInterval(of: component, for: date)
        }
        let periods: [(String, DateInterval?)] = [
            ("today", window(.day)),
            ("this week", window(.weekOfYear)),
            ("this month", window(.month)),
            ("last month", window(.month, offset: -1))
        ]
        let currencies = Set(transactions.map(\.currency)).sorted()
        for (label, interval) in periods {
            guard let interval else { continue }
            let inPeriod = transactions.filter { interval.contains($0.date) }
            for currency in currencies {
                let items = inPeriod.filter { $0.currency == currency }
                let spent = sum(items.filter { $0.direction == "debit" && !$0.isReversal })
                let income = sum(items.filter { $0.direction == "credit" && !$0.isReversal })
                if spent > 0 || income > 0 {
                    lines.append("Spent \(label): \(fmt(spent)) \(currency); income \(label): \(fmt(income)) \(currency); \(items.count) transactions.")
                }
            }
        }

        if let month = window(.month) {
            let debits = transactions.filter { month.contains($0.date) && $0.direction == "debit" && !$0.isReversal }
            let byCategory = Dictionary(grouping: debits) { "\($0.category) (\($0.currency))" }
                .mapValues(sum).sorted { $0.value > $1.value }.prefix(5)
            if !byCategory.isEmpty {
                lines.append("Top categories this month: " + byCategory.map { "\($0.key) \(fmt($0.value))" }.joined(separator: ", ") + ".")
            }
            let byMerchant = Dictionary(grouping: debits.filter { $0.merchant != nil }) { "\($0.merchant ?? "") (\($0.currency))" }
                .mapValues(sum).sorted { $0.value > $1.value }.prefix(5)
            if !byMerchant.isEmpty {
                lines.append("Top merchants this month: " + byMerchant.map { "\($0.key) \(fmt($0.value))" }.joined(separator: ", ") + ".")
            }
        }

        let upcoming = subscriptions
            .filter { $0.isActive && $0.nextPaymentDate <= (calendar.date(byAdding: .day, value: 30, to: now) ?? now) }
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
        if !upcoming.isEmpty {
            lines.append("Subscriptions due in 30 days: " + upcoming.map {
                "\($0.name) \(fmt($0.amount)) \($0.currency) on \($0.nextPaymentDate.formatted(date: .abbreviated, time: .omitted))"
            }.joined(separator: "; ") + ".")
        }
        let suggested = subscriptions.filter(\.needsConfirmation).map(\.name)
        if !suggested.isEmpty {
            lines.append("Possible subscriptions waiting for the user to confirm: \(suggested.joined(separator: ", ")).")
        }

        let recent = transactions.sorted { $0.date > $1.date }.prefix(10)
        if !recent.isEmpty {
            lines.append("Latest transactions:")
            for item in recent {
                let sign = item.direction == "credit" ? "+" : "-"
                lines.append("- \(item.date.formatted(date: .abbreviated, time: .omitted)) \(item.merchant ?? item.category) \(sign)\(fmt(item.amount)) \(item.currency) [\(item.category)]")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func sum(_ items: [GhafTransaction]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + $1.amount }
    }

    static func fmt(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

/// Decides whether a chat message is a question or a spoken/typed purchase.
enum GhafMessageIntent {
    static func isQuestion(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("?") || lower.contains("؟") { return true }
        let starters = ["how", "what", "which", "when", "where", "why", "who", "am ", "do ", "did ", "does ", "is ", "are ",
                        "can ", "could ", "should ", "show", "list", "tell", "give", "compare", "explain", "summar",
                        "كم", "وين", "ايش", "إيش", "شو", "هل", "ليش", "لماذا", "متى", "كيف", "ما ", "ماذا", "اعرض", "أعطني", "اعطني", "قارن"]
        return starters.contains { lower.hasPrefix($0) }
    }

    /// Transactions described in the message, or empty when it is a question or has no amount.
    static func drafts(in text: String, baseCurrency: String) -> [GhafVoiceTransactionDraft] {
        guard !isQuestion(text) else { return [] }
        let isArabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
        return GhafVoiceTransactionParser.parse(text, languageCode: isArabic ? "ar" : "en", baseCurrency: baseCurrency)
            .filter { $0.amount > 0 }
    }
}

/// Chat brain: Apple's on-device model when available, otherwise grounded rule-based answers.
@MainActor
final class GhafAssistant: ObservableObject {
    enum Engine { case onDevice, basic }

    var engine: Engine {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return .onDevice }
        #endif
        return .basic
    }

    /// Streams the reply text. `history` is the recent conversation, oldest first.
    func reply(
        to question: String,
        facts: String,
        history: [(isUser: Bool, text: String)],
        languageCode: String
    ) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), engine == .onDevice {
            return onDeviceReply(to: question, facts: facts, history: history, languageCode: languageCode)
        }
        #endif
        let answer = Self.basicAnswer(to: question, facts: facts, languageCode: languageCode)
        return AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func onDeviceReply(
        to question: String,
        facts: String,
        history: [(isUser: Bool, text: String)],
        languageCode: String
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = """
        You are Ghaf AI, a warm, concise personal finance assistant inside the Ghaf app (UAE).
        Answer only from the FACTS below. Quote amounts exactly as written with their currency.
        Never invent transactions, balances or subscriptions, and never add amounts in different currencies.
        If the facts do not contain the answer, say so briefly and suggest what the user can record.
        Reply in \(languageCode == "ar" ? "Arabic (Gulf-friendly Modern Standard Arabic)" : "English"), in 1-4 short sentences or a short list.
        Users can add a purchase by just typing or saying it, e.g. "35 AED lunch".

        FACTS:
        \(facts)
        """
        let recent = history.suffix(6).map { ($0.isUser ? "User: " : "Ghaf: ") + $0.text }.joined(separator: "\n")
        let prompt = recent.isEmpty ? question : "Conversation so far:\n\(recent)\n\nUser: \(question)"

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    // Context too long, unsupported language, guardrails: fall back to grounded answers.
                    Logger(subsystem: "com.ghaf.app", category: "ai").error("On-device model failed: \(String(describing: error), privacy: .public)")
                    continuation.yield(Self.basicAnswer(to: question, facts: facts, languageCode: languageCode))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif

    /// Keyword answers built only from the facts text, used without Apple Intelligence.
    static func basicAnswer(to question: String, facts: String, languageCode: String) -> String {
        let q = question.lowercased()
        let ar = languageCode == "ar"
        let lines = facts.components(separatedBy: "\n")
        func pick(_ prefix: String) -> [String] { lines.filter { $0.hasPrefix(prefix) } }

        if q.contains("subscri") || q.contains("اشتراك") {
            let due = pick("Subscriptions due")
            return due.first ?? (ar ? "لا توجد اشتراكات مستحقة خلال ٣٠ يوماً." : "No subscriptions are due in the next 30 days.")
        }
        if q.contains("balance") || q.contains("have") || q.contains("رصيد") || q.contains("عندي") {
            let start = lines.firstIndex { $0.hasPrefix("Accounts") }
            guard let start else { return ar ? "لا توجد حسابات بعد." : "You have no accounts yet." }
            return lines[start...].prefix { $0.hasPrefix("Accounts") || $0.hasPrefix("- ") }.joined(separator: "\n")
        }
        if q.contains("categor") || q.contains("most") || q.contains("فئة") || q.contains("أكثر") || q.contains("وين") {
            return (pick("Top categories") + pick("Top merchants")).joined(separator: "\n").nilIfEmpty
                ?? (ar ? "لا توجد مصاريف هذا الشهر بعد." : "No spending recorded this month yet.")
        }
        let period: String
        if q.contains("today") || q.contains("اليوم") { period = "today" }
        else if q.contains("week") || q.contains("أسبوع") || q.contains("اسبوع") { period = "this week" }
        else if q.contains("last month") || q.contains("الشهر الماضي") { period = "last month" }
        else { period = "this month" }
        if q.contains("spen") || q.contains("صرف") || q.contains("income") || q.contains("دخل") || q.contains("month") || q.contains("شهر") {
            return pick("Spent \(period)").joined(separator: "\n").nilIfEmpty
                ?? (ar ? "لا توجد عمليات مسجلة لهذه الفترة." : "Nothing recorded for \(period) yet.")
        }
        return ar
            ? "أستطيع الإجابة عن رصيدك، مصروف اليوم أو الأسبوع أو الشهر، أكثر فئة، والاشتراكات القادمة. ويمكنك كتابة أو قول مشترياتك مثل «٣٥ درهم غداء» لأسجلها."
            : "Ask me about your balance, spending today, this week or this month, your top category, or upcoming subscriptions. You can also type or say a purchase like \"35 AED lunch\" and I'll log it."
    }
}

/// Saves confirmed transaction drafts and learns merchant categories from them.
enum GhafDraftSaver {
    @MainActor
    static func save(
        _ drafts: [GhafVoiceTransactionDraft],
        preferredAccountID: UUID?,
        accounts: [GhafAccount],
        context: ModelContext,
        note: String
    ) throws {
        for draft in drafts {
            let direction = TransactionDirection(rawValue: draft.direction) ?? .debit
            let parsed = ParsedTransaction(amount: draft.amount, currency: draft.currency, merchant: draft.merchant.isEmpty ? nil : draft.merchant, date: draft.date, direction: direction, confidence: 0.82, bank: nil)
            let category = draft.category == "Other"
                ? ((try? MerchantCategorizer.category(for: draft.merchant, direction: direction, context: context)) ?? "Other")
                : draft.category
            let preferred = accounts.first { $0.id == preferredAccountID && !$0.isArchived && $0.currency == draft.currency }
            let assigned = preferred ?? accounts.first { !$0.isArchived && $0.currency == draft.currency }
            let transaction = GhafTransaction(
                fingerprint: "voice-\(UUID().uuidString)",
                parsed: parsed,
                category: category,
                needsReview: draft.merchant.isEmpty || category == "Other" || assigned == nil,
                isReversal: false,
                accountID: assigned?.id
            )
            transaction.note = note
            transaction.subcategory = category == draft.category ? draft.subcategory : nil
            context.insert(transaction)
            if let merchant = transaction.merchant, !merchant.isEmpty, category != "Other" {
                try MerchantCategorizer.learn(merchant: merchant, category: category, subcategory: transaction.subcategory, context: context, saveImmediately: false)
            }
        }
        try context.save()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
