import Foundation

private enum BankPatterns {
    static let amounts = [
        #"(?i)\b(?:AED|USD|EUR|GBP|SAR|KWD|BHD|OMR|QAR)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b"#,
        #"(?i)\b([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:AED|USD|EUR|GBP|SAR|KWD|BHD|OMR|QAR)\b"#,
        #"(?i)\b(?:amount|of|for)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b"#
    ]

    static let merchants = [
        #"(?i)\bat\s+(.+?)(?=\s+(?:available\s+balance|balance|on\s+\d{1,4}[/-]\d)|[.;\n]|$)"#,
        #"(?i)\bmerchant(?:\s+name)?\s*[:\-]\s*(.+?)(?=\s+(?:available\s+balance|balance|on\s+\d{1,4}[/-]\d)|[.;\n]|$)"#
    ]

    static let dates = [
        #"(?i)\b(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#
    ]

    static let debits = [
        #"(?i)\bdebit(?:ed)?\b"#, #"(?i)\bpurchase(?:d)?\b"#,
        #"(?i)\bspent\b"#, #"(?i)\bpaid\b"#, #"(?i)\bpayment\b"#,
        #"(?i)\bwithdraw(?:al|n)?\b"#, #"(?i)\bcharged\b"#,
        #"(?i)\bcard\s+used\b"#
    ]

    static let credits = [
        #"(?i)\bcredited\b"#, #"(?i)\breceived\b"#,
        #"(?i)\brefund(?:ed)?\b"#, #"(?i)\bsalary\b"#,
        #"(?i)\bdeposit(?:ed)?\b"#, #"(?i)\bcashback\b"#
    ]

    static let transactionSignals = debits + credits + [
        #"(?i)\bwas\s+made\b"#, #"(?i)\btransaction\b"#,
        #"(?i)\breversal\b"#
    ]
}

private enum Regex {
    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    static func matches(_ patterns: [String], in text: String) -> Bool {
        patterns.contains { captures($0, in: text) != nil }
    }
}

private struct AmountResult {
    let amount: Decimal
    let currency: String
    let hasExplicitCurrency: Bool
}

private enum TransactionExtractor {
    static func amount(_ message: String, defaultCurrency: String) -> AmountResult? {
        for pattern in BankPatterns.amounts {
            guard let groups = Regex.captures(pattern, in: message),
                  groups.count > 1, !groups[1].isEmpty else { continue }

            let number = groups[1].replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(
                string: number,
                locale: Locale(identifier: "en_US_POSIX")
            ), value > 0 else { continue }

            let currencyPattern = #"(?i)\b(AED|USD|EUR|GBP|SAR|KWD|BHD|OMR|QAR)\b"#
            let currency = Regex.captures(currencyPattern, in: groups[0])?[1]
            return AmountResult(
                amount: value,
                currency: currency?.uppercased() ?? defaultCurrency,
                hasExplicitCurrency: currency != nil
            )
        }
        return nil
    }

    static func merchant(_ message: String) -> String? {
        for pattern in BankPatterns.merchants {
            guard let groups = Regex.captures(pattern, in: message),
                  groups.count > 1 else { continue }
            let value = groups[1].trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func date(_ message: String, fallback: Date) -> (Date, Bool) {
        guard let groups = Regex.captures(BankPatterns.dates[0], in: message),
              groups.count > 1, !groups[1].isEmpty else {
            return (fallback, false)
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "dd/MM/yyyy HH:mm", "d/M/yyyy HH:mm",
            "dd-MM-yyyy HH:mm", "d-M-yyyy HH:mm",
            "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy",
            "dd/MM/yy", "d/M/yy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.isLenient = false

        for format in formats {
            formatter.dateFormat = format
            if let value = formatter.date(from: groups[1]) { return (value, true) }
        }
        return (fallback, false)
    }

    static func direction(_ message: String) -> (TransactionDirection, Bool) {
        let debit = Regex.matches(BankPatterns.debits, in: message)
        let credit = Regex.matches(BankPatterns.credits, in: message)
        guard debit != credit else { return (.debit, false) }
        return credit ? (.credit, true) : (.debit, true)
    }
}

private enum Confidence {
    static func score(
        currency: Bool,
        merchant: Bool,
        date: Bool,
        bank: Bool,
        transactionSignal: Bool
    ) -> Double {
        var result = 0.42 // Amount successfully extracted.
        result += currency ? 0.12 : -0.08
        if merchant { result += 0.10 }
        if date { result += 0.08 }
        if bank { result += 0.04 }
        if transactionSignal { result += 0.04 }
        result += 0.20 // The parser requires an unambiguous direction.
        return min(max(result, 0.0), 1.0)
    }
}

struct RegexBankMessageRule: BankMessageRule {
    let bankName: String?
    private let identifyingTerms: [String]

    init(bankName: String?, identifyingTerms: [String]) {
        self.bankName = bankName
        self.identifyingTerms = identifyingTerms
    }

    func matches(message: String, sender: String?) -> Bool {
        let text = "\(sender ?? "") \(message)"
        return identifyingTerms.contains {
            text.range(of: $0, options: [.caseInsensitive]) != nil
        }
    }

    func parse(
        message: String,
        sender: String?,
        referenceDate: Date,
        defaultCurrency: String
    ) -> ParsedTransaction? {
        guard let amount = TransactionExtractor.amount(
            message,
            defaultCurrency: defaultCurrency
        ) else { return nil }

        let direction = TransactionExtractor.direction(message)
        // Amount-only or balance-only messages are not transactions.
        guard direction.1 else { return nil }

        let merchant = TransactionExtractor.merchant(message)
        let date = TransactionExtractor.date(message, fallback: referenceDate)
        let hasSignal = Regex.matches(BankPatterns.transactionSignals, in: message)

        let confidence = Confidence.score(
            currency: amount.hasExplicitCurrency,
            merchant: merchant != nil,
            date: date.1,
            bank: bankName != nil,
            transactionSignal: hasSignal
        )

        return ParsedTransaction(
            amount: amount.amount,
            currency: amount.currency,
            merchant: merchant,
            date: date.0,
            direction: direction.0,
            confidence: confidence,
            bank: bankName
        )
    }
}

struct GenericBankMessageRule: BankMessageRule {
    let bankName: String? = nil
    private let rule = RegexBankMessageRule(bankName: nil, identifyingTerms: [])

    func matches(message: String, sender: String?) -> Bool { true }

    func parse(
        message: String,
        sender: String?,
        referenceDate: Date,
        defaultCurrency: String
    ) -> ParsedTransaction? {
        rule.parse(
            message: message,
            sender: sender,
            referenceDate: referenceDate,
            defaultCurrency: defaultCurrency
        )
    }
}

enum BankRuleRegistry {
    static let defaultRules: [any BankMessageRule] = [
        RegexBankMessageRule(bankName: "mbank", identifyingTerms: ["mbank", "m bank"]),
        RegexBankMessageRule(bankName: "Mashreq", identifyingTerms: ["mashreq"]),
        RegexBankMessageRule(bankName: "iVESTOR", identifyingTerms: ["ivestor"]),
        RegexBankMessageRule(bankName: "ruya", identifyingTerms: ["ruya"])
    ]
}

enum MessageNoiseFilter {
    private static let ignored = [
        #"(?i)\bOTP\b"#,
        #"(?i)\bone[-\s]?time\s+(?:password|code)\b"#,
        #"(?i)\bverification\s+code\b"#,
        #"(?i)\bpromo(?:tion)?\b"#,
        #"(?i)\bspecial\s+offer\b"#,
        #"(?i)\bdiscount\s+code\b"#,
        #"(?i)\blimited[-\s]?time\s+offer\b"#,
        #"(?i)\bsecurity\s+alert\b"#,
        #"(?i)\bsuspicious\s+(?:login|activity)\b"#,
        #"(?i)\blogin\s+attempt\b"#,
        #"(?i)\bpassword\s+reset\b"#,
        #"(?i)\bdo\s+not\s+share\b"#,
        #"(?i)\bnever\s+share\b"#,
        // A transfer request is not proof that funds have moved.
        #"(?i)\brequest\s+received\s+for\s+fund\s+transfer\b"#,
        #"(?i)\btransfer\s+request\s+(?:received|created|submitted)\b"#,
        #"(?i)\brequest\s+to\s+transfer\b"#
    ]

    static func shouldIgnore(_ message: String) -> Bool {
        Regex.matches(ignored, in: message)
    }
}
