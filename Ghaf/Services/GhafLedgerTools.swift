import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The ledger the on-device model's tools read, set on the main actor right before each reply.
@MainActor
enum GhafLedgerContext {
    static var accounts: [GhafAccount] = []
    static var transactions: [GhafTransaction] = []
    static var subscriptions: [GhafSubscription] = []
    static var currency = "AED"
    static var languageCode = "en"
    /// Set by the chart tool when the model decides a chart helps; read once by the chat.
    static var requestedChart: (kind: String, style: String)?
}

#if canImport(FoundationModels)
/// Lets the model ask the ledger any money question and get exact, computed numbers back.
@available(iOS 26.0, *)
struct GhafLedgerTool: Tool {
    let name = "ledger"
    let description = """
    Answers a money question from the user's own records with exact numbers: spending for a period, \
    category or merchant; comparisons with the previous period; biggest purchase; income; balances; \
    subscriptions due; month-end forecast. Ask one specific question per call.
    """

    @Generable
    struct Arguments {
        @Guide(description: "One precise question in English, e.g. 'How much did I spend on Food last month?'")
        var question: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            GhafLedgerAnswers.answer(
                to: arguments.question,
                accounts: GhafLedgerContext.accounts,
                transactions: GhafLedgerContext.transactions,
                subscriptions: GhafLedgerContext.subscriptions,
                currency: GhafLedgerContext.currency,
                languageCode: "en"
            ) ?? "The records have no answer to that question."
        }
    }
}

/// Lets the model attach a chart to its reply; the chart itself is drawn from the ledger.
@available(iOS 26.0, *)
struct GhafChartTool: Tool {
    let name = "showChart"
    let description = "Shows a chart under your reply. Use it when a picture makes the answer clearer."

    @Generable
    struct Arguments {
        @Guide(description: "categories: spending by category this month; week: the last 7 days; compare: this month vs last month; trend: this month day by day",
               .anyOf(["categories", "week", "compare", "trend"]))
        var kind: String
        @Guide(description: "bar for comparing amounts, donut for shares of a whole, rose for a petal-style breakdown, line for change over time",
               .anyOf(["bar", "donut", "rose", "line"]))
        var style: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { GhafLedgerContext.requestedChart = (arguments.kind, arguments.style) }
        return "A \(arguments.style) \(arguments.kind) chart will be shown under your reply."
    }
}
#endif
