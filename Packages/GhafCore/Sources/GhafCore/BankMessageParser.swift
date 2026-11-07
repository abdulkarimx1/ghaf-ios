import Foundation

public struct BankMessageParser {

    private let bankRules: [any BankMessageRule]
    private let genericRule: any BankMessageRule

    public let defaultCurrency: String
    public let reviewConfidenceThreshold: Double

    public init(
        defaultCurrency: String = "AED",
        reviewConfidenceThreshold: Double = 0.80
    ) {
        self.bankRules = BankRuleRegistry.defaultRules
        self.genericRule = GenericBankMessageRule()

        self.defaultCurrency = defaultCurrency.uppercased()

        self.reviewConfidenceThreshold = min(
            max(reviewConfidenceThreshold, 0.0),
            1.0
        )
    }

    public init(
        bankRules: [any BankMessageRule],
        genericRule: any BankMessageRule,
        defaultCurrency: String = "AED",
        reviewConfidenceThreshold: Double = 0.80
    ) {
        self.bankRules = bankRules
        self.genericRule = genericRule

        self.defaultCurrency = defaultCurrency.uppercased()

        self.reviewConfidenceThreshold = min(
            max(reviewConfidenceThreshold, 0.0),
            1.0
        )
    }

    public func parse(
        _ rawMessage: String,
        sender: String? = nil,
        referenceDate: Date = Date()
    ) -> ParsedTransaction? {

        let message = rawMessage.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !message.isEmpty else {
            return nil
        }

        guard !MessageNoiseFilter.shouldIgnore(message) else {
            return nil
        }

        // Try bank-specific rules first.
        for rule in bankRules {

            guard rule.matches(
                message: message,
                sender: sender
            ) else {
                continue
            }

            if let transaction = rule.parse(
                message: message,
                sender: sender,
                referenceDate: referenceDate,
                defaultCurrency: defaultCurrency
            ) {
                return transaction
            }
        }

        // Generic fallback for unknown banks.
        return genericRule.parse(
            message: message,
            sender: sender,
            referenceDate: referenceDate,
            defaultCurrency: defaultCurrency
        )
    }

    public func shouldSendToReview(
        _ transaction: ParsedTransaction
    ) -> Bool {

        return transaction.confidence < reviewConfidenceThreshold
    }
}
