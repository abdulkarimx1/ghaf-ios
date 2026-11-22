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
        memories: [GhafMemory] = [],
        now: Date = .now
    ) -> String {
        let calendar = GhafCalendar.current
        var lines: [String] = ["Today is \(now.formatted(date: .complete, time: .omitted))."]

        let open = accounts.filter { !$0.isArchived }
        if open.isEmpty {
            lines.append("The user has no accounts yet.")
        } else {
            lines.append("Accounts (balance each, never add different currencies):")
            for account in open {
                let balance = GhafAccountBalanceCalculator.balance(for: account, transactions: transactions)
                lines.append("- \(account.name): \(fmt(balance, currency: account.currency)) \(account.currency)")
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
                let spent = spendingSum(items)
                let income = items.reduce(Decimal.zero) { $0 + $1.incomeAmount }
                if spent > 0 || income > 0 {
                    lines.append("Spent \(label) (refunds subtracted): \(fmt(spent, currency: currency)) \(currency); income \(label): \(fmt(income, currency: currency)) \(currency); \(items.count) transactions.")
                }
            }
        }

        if let month = window(.month) {
            let debits = transactions.filter { month.contains($0.date) && $0.isExpense }
            let categoryTotals: [(String, Decimal, String)] = Dictionary(grouping: debits) { "\($0.category) (\($0.currency))" }
                .map { key, items in (key, spendingSum(items), items[0].currency) }
                .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
            let byCategory = categoryTotals.prefix(5)
            if !byCategory.isEmpty {
                lines.append("Top categories this month: " + byCategory.map { "\($0.0) \(fmt($0.1, currency: $0.2))" }.joined(separator: ", ") + ".")
            }
            let merchantTotals: [(String, Decimal, String)] = Dictionary(grouping: debits.filter { GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) != nil }) { "\(GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) ?? "") (\($0.currency))" }
                .map { key, items in (key, spendingSum(items), items[0].currency) }
                .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
            let byMerchant = merchantTotals.prefix(5)
            if !byMerchant.isEmpty {
                lines.append("Top merchants this month: " + byMerchant.map { "\($0.0) \(fmt($0.1, currency: $0.2))" }.joined(separator: ", ") + ".")
            }
        }

        let upcoming = subscriptions
            .filter { $0.isActive && $0.nextPaymentDate <= (calendar.date(byAdding: .day, value: 30, to: now) ?? now) }
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
        if !upcoming.isEmpty {
            lines.append("Subscriptions due in 30 days: " + upcoming.map {
                "\($0.name) \(fmt($0.amount, currency: $0.currency)) \($0.currency) on \($0.nextPaymentDate.formatted(date: .abbreviated, time: .omitted))"
            }.joined(separator: "; ") + ".")
        }
        let suggested = subscriptions.filter(\.needsConfirmation).map(\.name)
        if !suggested.isEmpty {
            lines.append("Possible subscriptions waiting for the user to confirm: \(suggested.joined(separator: ", ")).")
        }

        let remembered = memories.sorted { $0.updatedAt > $1.updatedAt }.prefix(30)
        if !remembered.isEmpty {
            lines.append("What Ghaf remembers about the user:")
            lines.append(contentsOf: remembered.map { "- \($0.text)" })
            remembered.forEach { $0.lastUsedAt = now }
        }

        let recent = transactions.sorted { $0.date > $1.date }.prefix(10)
        if !recent.isEmpty {
            lines.append("Latest transactions:")
            for item in recent {
                let sign = item.direction == "credit" ? "+" : "-"
                lines.append("- \(item.date.formatted(date: .abbreviated, time: .omitted)) \(GhafMerchantAliasStore.displayName(item.rawMerchant ?? item.merchant) ?? item.category) \(sign)\(fmt(item.amount, currency: item.currency)) \(item.currency) [\(item.category)]")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func spendingSum(_ items: [GhafTransaction]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + $1.spendingAmount }
    }

    static func sum(_ items: [GhafTransaction]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + $1.amount }
    }

    static func fmt(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = GhafCurrencyDigits.fractionDigits(for: currency)
        formatter.maximumFractionDigits = GhafCurrencyDigits.fractionDigits(for: currency)
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
    enum Engine { case cloud, onDevice, basic }

    /// The user's opt-in cloud Worker first, then Apple's on-device model, then grounded basic answers.
    var engine: Engine {
        if GhafCloudAI.isEnabled { return .cloud }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return .onDevice }
        #endif
        return .basic
    }

    /// Streams the reply text. `history` is the recent conversation, oldest first.
    /// `direct` is the ledger's own worded answer when the question is about money; it is what the
    /// basic engine says, and the on-device model must keep its numbers.
    func reply(
        to question: String,
        facts: String,
        direct: String? = nil,
        history: [(isUser: Bool, text: String)],
        languageCode: String
    ) -> AsyncThrowingStream<String, Error> {
        let fallback = direct ?? Self.basicAnswer(to: question, facts: facts, languageCode: languageCode,
                                                  avoiding: Set(history.filter { !$0.isUser }.map(\.text)))
        if engine == .cloud {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let reply = try await GhafCloudAI.reply(question: question, facts: facts, direct: direct,
                                                               history: history, languageCode: languageCode)
                        await Self.reveal(Self.groundedReply(reply, question: question, facts: facts, direct: direct,
                                                             history: history, languageCode: languageCode), into: continuation)
                    } catch GhafCloudAI.Failure.dailyLimit {
                        await Self.reveal(fallback + (languageCode == "ar"
                            ? "\n\n(وصل غاف AI إلى الحد المجاني اليوم. أكملت الإجابة من جهازك.)"
                            : "\n\n(Ghaf AI has reached today's free limit. I finished this answer on your iPhone.)"), into: continuation)
                    } catch {
                        // Offline or the server failed: the ledger's answer still comes from the device.
                        Logger(subsystem: "com.ghaf.app", category: "ai").error("Cloud AI failed: \(String(describing: error), privacy: .public)")
                        await Self.reveal(fallback, into: continuation)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), engine == .onDevice {
            let grounded = direct.map { facts + "\nDIRECT ANSWER FROM THE LEDGER (keep these exact numbers): \($0)" } ?? facts
            return onDeviceReply(to: question, facts: grounded, direct: direct, history: history, languageCode: languageCode)
        }
        #endif
        return AsyncThrowingStream { continuation in
            let task = Task {
                await Self.reveal(fallback, into: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func groundedReply(_ reply: String, question: String, facts: String, direct: String?,
                                      history: [(isUser: Bool, text: String)], languageCode: String) -> String {
        let sources = [facts, direct ?? "", question] + history.map(\.text)
        let unsupported = GroundedNumbers.unsupported(in: reply, sources: sources)
        guard !unsupported.isEmpty else { return reply }
        Logger(subsystem: "com.ghaf.app", category: "ai").warning("Grounding replaced or flagged \(unsupported.count, privacy: .public) unsupported figures")
        if let direct { return direct }
        return reply + (languageCode == "ar"
            ? "\n\n(بعض الأرقام هنا غير موجودة في سجلاتك في غاف، فتحقق منها.)"
            : "\n\n(Some figures here aren't in your Ghaf records, so double-check them.)")
    }

    /// Shows an answer that arrived whole a few words at a time, as the on-device model's real stream does.
    /// The text is final before the first word appears; this only paces how it is drawn.
    static func reveal(_ text: String, into continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > 6 else { continuation.yield(text); return }
        var shown = 0
        while shown < words.count {
            shown = min(words.count, shown + 2)
            continuation.yield(words.prefix(shown).joined(separator: " "))
            if shown < words.count { try? await Task.sleep(for: .milliseconds(28)) }
            if Task.isCancelled { continuation.yield(text); return }
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func onDeviceReply(
        to question: String,
        facts: String,
        direct: String?,
        history: [(isUser: Bool, text: String)],
        languageCode: String
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = """
        You are Ghaf AI, a warm, concise personal finance assistant inside the Ghaf app (UAE).
        Answer only from the FACTS below or from the ledger tool. Quote amounts exactly as written with their currency.
        For any number the FACTS do not contain (another period, a category, a store), call the ledger tool.
        Call showChart when a chart makes the answer clearer.
        Use the memory tool only when the user explicitly asks you to remember or forget something; never save inferred facts.
        When a DIRECT ANSWER FROM THE LEDGER is given, answer with it in natural words, keeping every number,
        then add at most one short, useful observation or tip drawn from the facts.
        Never invent transactions, balances or subscriptions, and never add amounts in different currencies.
        If the facts do not contain the answer, say so briefly and suggest what the user can record.
        If the message is not about money (weather, jokes, sports, small talk), reply in one short, warm line with a
        light touch of humour, stay professional, then offer one thing you can do with their finances.
        Never repeat a sentence you already said in this conversation; vary your wording.
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
                    let session = LanguageModelSession(tools: [GhafLedgerTool(), GhafChartTool(), GhafMemoryTool()], instructions: instructions)
                    var finalText = ""
                    for try await snapshot in session.streamResponse(to: prompt) {
                        finalText = snapshot.content
                        continuation.yield(finalText)
                    }
                    let corrected = Self.groundedReply(finalText, question: question, facts: facts, direct: direct,
                                                       history: history, languageCode: languageCode)
                    if corrected != finalText { continuation.yield(corrected) }
                    continuation.finish()
                } catch {
                    // Context too long, unsupported language, guardrails: fall back to grounded answers.
                    Logger(subsystem: "com.ghaf.app", category: "ai").error("On-device model failed: \(String(describing: error), privacy: .public)")
                    continuation.yield(direct ?? Self.basicAnswer(to: question, facts: facts, languageCode: languageCode,
                                                                  avoiding: Set(history.filter { !$0.isUser }.map(\.text))))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif

    /// Keyword answers built only from the facts text, used without Apple Intelligence.
    static func basicAnswer(to question: String, facts: String, languageCode: String, avoiding: Set<String> = []) -> String {
        let q = question.lowercased()
        let ar = languageCode == "ar"
        let lines = facts.components(separatedBy: "\n")
        func pick(_ prefix: String) -> [String] { lines.filter { $0.hasPrefix(prefix) } }

        if q.contains("subscri") || q.contains("اشتراك") {
            let due = pick("Subscriptions due")
            return due.first ?? (ar ? "لا توجد اشتراكات مستحقة خلال ٣٠ يوماً." : "No subscriptions are due in the next 30 days.")
        }
        if q.contains("balance") || q.contains("do i have") || q.contains("رصيد") || q.contains("عندي") {
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
        // Money questions are handled above; only then is it small talk or something Ghaf did not understand.
        return GhafSmallTalk.reply(to: question, languageCode: languageCode, avoiding: avoiding)
            ?? GhafSmallTalk.notUnderstood(question, languageCode: languageCode, avoiding: avoiding)
    }
}

/// Saves confirmed transaction drafts and learns merchant categories from them.
enum GhafDraftSaver {
    /// Returns the new transactions' ids, in draft order.
    @MainActor
    @discardableResult
    static func save(
        _ drafts: [GhafVoiceTransactionDraft],
        preferredAccountID: UUID?,
        accounts: [GhafAccount],
        context: ModelContext,
        note: String
    ) throws -> [UUID] {
        var ids: [UUID] = []
        let settings = try context.fetch(FetchDescriptor<GhafSettings>()).first
        for draft in drafts {
            if draft.category != "Other", let settings { settings.addCategory(draft.category, subcategory: draft.subcategory) }
            let direction = TransactionDirection(rawValue: draft.direction) ?? .debit
            let parsed = ParsedTransaction(amount: draft.amount, currency: draft.currency, merchant: draft.merchant.isEmpty ? nil : draft.merchant, date: draft.date, direction: direction, confidence: 0.82, bank: nil)
            let category = draft.category == "Other"
                ? ((try? MerchantCategorizer.category(for: draft.merchant, direction: direction, context: context)) ?? "Other")
                : draft.category
            let preferred = accounts.first { $0.id == preferredAccountID && !$0.isArchived && $0.currency == draft.currency }
            // Spoken and typed entries are usually cash: a cash wallet first, the primary account next.
            let active = accounts.filter { !$0.isArchived && $0.currency == draft.currency }
            let assigned = preferred ?? active.first { $0.type == .cash } ?? active.first { $0.isPrimary } ?? active.first
            let transaction = GhafTransaction(
                fingerprint: "voice-\(UUID().uuidString)",
                parsed: parsed,
                category: category,
                needsReview: draft.merchant.isEmpty || category == "Other" || assigned == nil,
                isReversal: false,
                accountID: assigned?.id
            )
            transaction.note = note
            ids.append(transaction.id)
            transaction.subcategory = category == draft.category ? draft.subcategory : nil
            context.insert(transaction)
            if let merchant = transaction.merchant, !merchant.isEmpty, category != "Other" {
                try MerchantCategorizer.learn(merchant: merchant, category: category, subcategory: transaction.subcategory, context: context, saveImmediately: false)
            }
        }
        try context.save()
        return ids
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
