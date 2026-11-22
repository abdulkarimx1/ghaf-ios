import Foundation

private enum BankPatterns {
    static let merchants = [
        #"(?i)\bat\s+(.+?)(?=\s+(?:(?:using|via)\s+(?:[\w-]+\s+){0,4}?(?:card|account)\b|with\s+(?:your\s+)?(?:[\w-]+\s+){0,1}?card\b|available\s+balance|balance|on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{1,4}[/-]\d|\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)))|[.;\n]|$)"#,
        #"(?:لدى|عند)\s+(.+?)(?=\s+(?:(?:باستخدام|بواسطة|ب)\s*بطاقة|الرصيد|بتاريخ|في\s+\d)|[.،;\n]|$)"#,
        #"(?i)\bmerchant(?:\s+name)?\s*[:\-]\s*(.+?)(?=\s+(?:available\s+balance|balance|on\s+\d{1,4}[/-]\d)|[.;\n]|$)"#
    ]

    static let dates = [
        #"(?i)\b(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#
    ]

    static let debits = [
        #"(?i)\bdebit(?:ed)?\b"#, #"(?i)\bpurchase(?:d)?\b"#,
        #"(?i)\bspent\b"#, #"(?i)\bpaid\b"#, #"(?i)\bpayment\b"#,
        #"(?i)\bwithdraw(?:al|n)?\b"#, #"(?i)\bcharged\b"#,
        #"(?i)\bcard\s+used\b"#,
        // «خصم» alone also means a promotional discount; only its deduction forms count.
        #"تم\s+(?:ال)?خصم|خُصم|خصم\s+مبلغ|مبلغ\s+مخصوم|شراء|سحب|دفع|مدين"#
    ]

    static let credits = [
        #"(?i)\bcredited\b"#, #"(?i)\breceived\b"#,
        #"(?i)\brefund(?:ed)?\b"#, #"(?i)\bsalary\b"#,
        #"(?i)\bdeposit(?:ed)?\b"#, #"(?i)\bcashback\b"#,
        #"إيداع|ايداع|استلام|راتب|دائن|إضافة|اضافة|وارد"#
    ]

    static let reversals = [#"(?i)\brevers(?:al|ed)\b"#, #"(?i)تم\s+عكس|عكس\s+(?:عملية|مبلغ)"#]
    static let refunds = [#"(?i)\brefund(?:ed)?\b"#, #"استرداد|مسترد"#]
    static let pending = [
        #"(?i)\bpending\b"#, #"(?i)\bon\s+hold\b"#, #"(?i)\bblocked\s+amount\b"#,
        #"(?i)\bpre-?authori[sz](?:ation|ed)\b"#, #"(?i)\bauthori[sz]ation\s+hold\b"#, #"قيد\s+المعالجة|معلق"#
    ]
    static let explicitDebit = [#"(?i)\bdebited\b"#, #"تم\s+خصم"#]

    /// Words that say money actually moved, not that it could ("debited", «تم خصم», "was made").
    static let completed = [
        #"(?i)\b(?:debited|credited|deducted|withdrawn|charged|spent|deposited|transferred|refunded|reversed)\b"#,
        #"(?i)\b(?:was|were|has\s+been|have\s+been)\s+(?:made|used|paid|completed|successful|approved|processed|received|sent)\b"#,
        #"(?i)\byou\s+(?:paid|spent|received|sent|withdrew)\b"#,
        #"(?i)\b(?:purchase|payment|withdrawal|debit|credit)\s+(?:of\s+)?(?:AED|USD|EUR|GBP|SAR|KWD|BHD|OMR|QAR)\s*[0-9]"#,
        #"(?i)\bcard\s+purchase\b"#, #"(?i)\b(?:salary|refund)\b"#,
        #"تم\s*(?:ال)?(?:خصم|شراء|سحب|إيداع|ايداع|تحويل|دفع|استلام|إضافة|اضافة|استرداد|عكس)|تمت\s+(?:عملية|العملية)|خُصم|أودع|عملية\s+شراء|سحب\s+نقدي|حوالة\s+(?:واردة|صادرة)|راتب"#
    ]

    /// The user's own card or account ("card ending 1234", "xxxx0000", «بطاقتك», «حسابك»).
    static let ownReference = [
        #"(?i)\b(?:card|account|a/c|acct)\s*(?:no\.?|number|ending(?:\s+(?:in|with))?)?\s*[:#]?\s*[x*•.\d]{3,}"#,
        #"(?i)\byour\s+(?:card|account|credit\s+card|debit\s+card)\b"#,
        #"(?:بطاقتك|بطاقتكم|حسابك|حسابكم|البطاقة\s+رقم|الحساب\s+رقم|المنتهية\s+ب)"#
    ]

    static let accountReferences = [
        #"(?i)\b(?:card|account|a/c|acct)\s*(?:(?:no\.?|number)\s*)?(?:ending(?:\s+(?:in|with))?\s*)?[*x•.\-\s]*(\d{3,})\b"#,
        #"(?i)\b(?:card|account)\s+ending\s+(?:in\s+)?(\d{3,})\b"#,
        #"(?:المنتهية\s+بـ?|(?:ال)?بطاقة\s+(?:رقم\s*)?|الحساب\s+رقم\s*)[*x•.\-\s]*(\d{3,})\b"#
    ]

    /// Marketing language: offers, rewards, links and invitations.
    static let marketing = [
        #"(?i)\b(?:offer|offers|deal|enjoy|win|reward|rewards|exclusive|apply\s+now|click|download|valid\s+(?:till|until)|t\s*&\s*c|terms\s+apply|up\s+to|discount|sale|voucher|coupon|instalment\s+plan|eligible)\b"#,
        #"(?i)https?://|www\.|\d+\s*%"#,
        #"استمتع|اربح|احصل|عرض|عروض|حصري|لفترة\s+محدودة|اضغط|سارع|قدم\s+الآن|قدّم|تطبق\s+الشروط|الشروط\s+والأحكام|كوبون|قسيمة|مكافأة|مكافآت|استرجاع\s+نقدي\s+يصل|يصل\s+إلى"#
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
    /// Codes always read in any letter case; every other ISO 4217 code counts only in capitals,
    /// so "TRY 597.60" is Turkish lira while "try 3 times" is not money.
    private static let familiarCodes: Set<String> = ["AED", "USD", "EUR", "GBP", "SAR", "KWD", "BHD", "OMR", "QAR"]
    private static let isoCodes = Set(Locale.commonISOCurrencyCodes)
    private static let number = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#

    static func amount(_ message: String, defaultCurrency: String) -> AmountResult? {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        // Every "CODE 12.34" or "12.34 CODE" in the message, earliest first.
        var found: [(position: Int, amount: Decimal, code: String)] = []
        for (pattern, codeGroup, numberGroup) in [(#"\b([A-Za-z]{3})\s*"# + number + #"\b"#, 1, 2),
                                                  (#"\b"# + number + #"\s*([A-Za-z]{3})\b"#, 2, 1)] {
            let expression = try! NSRegularExpression(pattern: pattern)
            for match in expression.matches(in: message, range: range) {
                guard let codeRange = Range(match.range(at: codeGroup), in: message),
                      let numberRange = Range(match.range(at: numberGroup), in: message),
                      let whole = Range(match.range, in: message) else { continue }
                let raw = String(message[codeRange])
                let code = raw.uppercased()
                guard familiarCodes.contains(code) || (raw == code && isoCodes.contains(code)),
                      let value = decimal(message[numberRange]), value > 0,
                      !followsBalanceLabel(message, before: whole.lowerBound) else { continue }
                found.append((match.range.location, value, code))
            }
        }
        if let first = found.min(by: { $0.position < $1.position }) {
            return AmountResult(amount: first.amount, currency: first.code, hasExplicitCurrency: true)
        }
        // No currency code: "amount 25", "of 25", "for 25".
        if let groups = Regex.captures(#"(?i)\b(?:amount|of|for)\s+"# + number + #"\b"#, in: message),
           groups.count > 1, let value = decimal(Substring(groups[1])), value > 0 {
            return AmountResult(amount: value, currency: defaultCurrency, hasExplicitCurrency: false)
        }
        return nil
    }

    private static func decimal(_ text: Substring) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }

    /// "Available Balance: AED 455.46" or «الرصيد المتاح 455.46 AED» reports what is left, not what moved.
    private static func followsBalanceLabel(_ message: String, before index: String.Index) -> Bool {
        let start = message.index(index, offsetBy: -30, limitedBy: message.startIndex) ?? message.startIndex
        let prefix = message[start..<index]
        return prefix.range(of: #"(?i)(?:\b(?:bal(?:ance)?|avl\.?\s*bal)\b(?:\s+(?:is|of|now|available))?|(?:ال)?رصيد(?:\s+(?:ال)?(?:متاح|حالي))?)[\s:.\-]*$"#,
                            options: .regularExpression) != nil
    }

    static func merchant(_ message: String) -> String? {
        for pattern in BankPatterns.merchants {
            guard let groups = Regex.captures(pattern, in: message),
                  groups.count > 1 else { continue }
            let value = groups[1].trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
            if !value.isEmpty { return MerchantName.clean(value) }
        }
        return nil
    }

    static func date(_ message: String, fallback: Date) -> (Date, Bool) {
        let spelled = #"(?i)((?:(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday),?\s+)?(?:\d{1,2}\s+[a-z]{3,9}\s+\d{4}|[a-z]{3,9}\s+\d{1,2},?\s+\d{4})(?:,?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)?)"#
        let rawDate = Regex.captures(BankPatterns.dates[0], in: message).flatMap { $0.count > 1 ? $0[1] : nil }
            ?? Regex.captures(spelled, in: message).flatMap { $0.count > 1 ? $0[1] : nil }
        guard let rawDate, !rawDate.isEmpty else { return (fallback, false) }
        let formats = [
            "EEEE, d MMMM yyyy, h:mm a", "d MMMM yyyy HH:mm", "d MMMM yyyy HH:mm:ss",
            "d MMM yyyy h:mm a", "d MMM yyyy HH:mm", "MMM d, yyyy h:mma", "MMM d, yyyy h:mm a",
            "d MMMM yyyy", "d MMM yyyy", "MMM d, yyyy",
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
            if let value = formatter.date(from: rawDate) { return (value, true) }
        }
        return (fallback, false)
    }

    static func kind(_ message: String) -> ParsedTransaction.Kind {
        if Regex.matches(BankPatterns.pending, in: message) { return .pending }
        if Regex.matches(BankPatterns.reversals, in: message) { return .reversal }
        if Regex.matches(BankPatterns.refunds, in: message) { return .refund }
        return .standard
    }

    static func direction(_ message: String, kind: ParsedTransaction.Kind) -> (TransactionDirection, Bool) {
        // "Reversal of purchase ..." names a debit word but returns money: credit unless it says debited.
        if kind == .refund || kind == .reversal {
            return (Regex.matches(BankPatterns.explicitDebit, in: message) ? .debit : .credit, true)
        }
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

        let kind = TransactionExtractor.kind(message)
        let direction = TransactionExtractor.direction(message, kind: kind)
        // Amount-only or balance-only messages are not transactions.
        guard direction.1 else { return nil }

        let merchant = TransactionExtractor.merchant(message)
        // Evidence that money moved. A bank sending a message proves nothing by itself.
        let completed = Regex.matches(BankPatterns.completed, in: message)
        let ownReference = Regex.matches(BankPatterns.ownReference, in: message)
        // An offer ("Enjoy 50 AED off…", «خصم ٢٠٪») is never a transaction unless it also reports a
        // completed movement on the user's own card or account.
        if Regex.matches(BankPatterns.marketing, in: message), !(completed && ownReference) { return nil }
        guard completed || ownReference || merchant != nil else { return nil }
        // No currency: only a recognised bank's message with clear evidence is kept, and only for review.
        if !amount.hasExplicitCurrency, bankName == nil || !(completed || ownReference) && merchant == nil { return nil }
        let date = TransactionExtractor.date(message, fallback: referenceDate)
        let accountRef = BankPatterns.accountReferences.lazy.compactMap { pattern in
            Regex.captures(pattern, in: message).flatMap { $0.count > 1 ? $0[1] : nil }
        }.first.flatMap { $0.count >= 3 ? String($0.suffix(4)) : nil }
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
            bank: bankName,
            kind: kind,
            accountRef: accountRef
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

/// Rewrites Arabic bank text into the forms the rules read: Western digits and ISO currency codes.
/// A bare "ريال" is left alone because it could be SAR, OMR or QAR; the default currency and review apply.
enum ArabicMessageNormalizer {
    private static let currencies: [(String, String)] = [
        (#"ريال\s+سعودي|ر\.\s?س\.?"#, "SAR"), (#"ريال\s+عماني|ر\.\s?ع\.?"#, "OMR"),
        (#"ريال\s+قطري|ر\.\s?ق\.?"#, "QAR"), (#"دينار\s+كويتي|د\.\s?ك\.?"#, "KWD"),
        (#"دينار\s+بحريني|د\.\s?ب\.?"#, "BHD"), (#"دراهم|درهم|د\.\s?إ\.?"#, "AED")
    ]

    static func normalize(_ text: String) -> String {
        var result = String(text.map { character -> Character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return character }
            switch scalar.value {
            case 0x0660...0x0669: return Character(String(scalar.value - 0x0660))
            case 0x06F0...0x06F9: return Character(String(scalar.value - 0x06F0))
            case 0x066B: return "."
            case 0x066C: return ","
            default: return character
            }
        })
        for (pattern, code) in currencies {
            result = result.replacingOccurrences(of: pattern, with: " \(code) ", options: .regularExpression)
        }
        return result
    }
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
        #"احصل\s+على|عرض\s+(?:خاص|حصري)|خصم\s+\d+\s*%|\d+\s*%\s*خصم"#,
        #"رمز\s+(?:التحقق|التفعيل|سري)|كلمة\s+(?:ال)?مرور\s+لمرة\s+واحدة|لا\s+تشارك"#,
        // Statements and payment reminders name an amount that has not moved.
        #"(?i)\b(?:minimum\s+(?:amount\s+)?due|payment\s+due|amount\s+due|due\s+(?:date|by|on)|statement\s+(?:is\s+)?(?:ready|generated|available))\b"#,
        #"المبلغ\s+المستحق|الحد\s+الأدنى\s+(?:للدفع|المستحق)|تاريخ\s+الاستحقاق|كشف\s+(?:حساب|البطاقة)|تذكير\s+بالدفع"#,
        // A transfer request is not proof that funds have moved.
        #"(?i)\brequest\s+received\s+for\s+fund\s+transfer\b"#,
        #"(?i)\btransfer\s+request\s+(?:received|created|submitted)\b"#,
        #"(?i)\brequest\s+to\s+transfer\b"#
    ]

    static func shouldIgnore(_ message: String) -> Bool {
        Regex.matches(ignored, in: message)
    }
}
