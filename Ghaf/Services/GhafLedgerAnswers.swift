import Foundation
import GhafCore

/// Direct, worded answers to money questions, computed from the ledger. The language model may
/// rephrase them, but every number comes from here. Amounts stay in one currency at a time.
enum GhafLedgerAnswers {

    struct ProgressQuery {
        let transactionCount: Int
        let purchaseCount: Int?
        let period: String
    }

    static func progressQuery(for question: String, transactions: [GhafTransaction], currency: String,
                              languageCode: String, now: Date = .now) -> ProgressQuery? {
        let q = question.lowercased()
        let words = ["spen", "cost", "expense", "purchase", "transaction", "income", "earn", "salary",
                     "where", "most", "top", "categor", "breakdown", "chart", "graph", "صرف", "مصروف",
                     "مشتري", "عملية", "دخل", "راتب", "وين", "أكثر", "اكثر", "فئة", "رسم"]
        guard words.contains(where: { q.contains($0) }),
              !["subscri", "اشتراك", "balance", "رصيد", "do i have", "عندي"].contains(where: { q.contains($0) }) else { return nil }
        let period = period(for: q, now: now)
        var items = transactions.filter { $0.currency == currency && period.interval.contains($0.date) && $0.isSpendingOrIncome }
        if let category = matchedCategory(in: q, transactions: transactions, languageCode: languageCode) {
            items = items.filter { $0.isExpense && $0.category == category }
        } else if let merchant = matchedMerchant(in: q, transactions: transactions) {
            items = items.filter { $0.isExpense && MerchantName.key(GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) ?? "") == merchant.key }
        }
        let purchaseQuery = ["spen", "cost", "expense", "purchase", "where", "most", "top", "categor", "breakdown", "chart", "graph",
                             "صرف", "مصروف", "مشتري", "دفعت", "وين", "أكثر", "اكثر", "فئة", "رسم"].contains { q.contains($0) }
        let purchases = purchaseQuery ? items.filter { $0.isExpense && $0.direction == "debit" && !$0.isReversal }.count : nil
        let calendar = GhafCalendar.current
        let end = min(now, period.interval.end.addingTimeInterval(-1))
        let locale = GhafLocale.locale(identifier: languageCode == "ar" ? "ar" : "en")
        let startMonth = period.interval.start.formatted(.dateTime.month(.abbreviated).locale(locale))
        let endMonth = end.formatted(.dateTime.month(.abbreviated).locale(locale))
        let startDay = period.interval.start.formatted(.dateTime.day().locale(locale))
        let endDay = end.formatted(.dateTime.day().locale(locale))
        let range = calendar.isDate(period.interval.start, equalTo: end, toGranularity: .month)
            ? "\(startDay)–\(endDay) \(startMonth)" : "\(startDay) \(startMonth)–\(endDay) \(endMonth)"
        return ProgressQuery(transactionCount: items.count, purchaseCount: purchases, period: range)
    }

    struct Period {
        let interval: DateInterval
        let previous: DateInterval?
        let en: String
        let ar: String
        let previousEn: String
        let previousAr: String
    }

    static func answer(
        to question: String,
        accounts: [GhafAccount],
        transactions: [GhafTransaction],
        subscriptions: [GhafSubscription],
        currency: String,
        languageCode: String,
        now: Date = .now
    ) -> String? {
        let q = question.lowercased()
        let ar = languageCode == "ar"
        func has(_ words: [String]) -> Bool { words.contains { q.contains($0) } }
        func money(_ value: Decimal, _ code: String = currency) -> String { GhafFormat.money(value, currency: code, languageCode: languageCode) }

        // Balances: one line per account, totals only within a currency.
        if has(["balance", "do i have", "how much money", "رصيد", "عندي", "كم معي", "فلوسي"]) {
            let open = accounts.filter { !$0.isArchived }
            guard !open.isEmpty else { return ar ? "ما عندك حسابات بعد. أضف حساباً من «الحسابات»." : "You have no accounts yet. Add one under Accounts." }
            let balances = GhafAccountBalanceCalculator.balances(accounts: open, transactions: transactions)
            let byCurrency = Dictionary(grouping: open.filter(\.includeInTotal), by: \.currency)
                .mapValues { $0.reduce(Decimal.zero) { $0 + (balances[$1.id] ?? $1.openingBalance) } }
            let totals = byCurrency.sorted { $0.key < $1.key }.map { money($0.value, $0.key) }.joined(separator: ar ? " و" : " and ")
            let top = open.sorted { (balances[$0.id] ?? 0) > (balances[$1.id] ?? 0) }.prefix(3)
                .map { "\($0.name) \(money(balances[$0.id] ?? $0.openingBalance, $0.currency))" }
                .joined(separator: ar ? "، " : ", ")
            return ar ? "إجمالي رصيدك \(totals). أكبر حساباتك: \(top)."
                      : "You have \(totals) in total. Largest accounts: \(top)."
        }

        // Subscriptions due soon.
        if has(["subscri", "renew", "اشتراك", "تجديد"]) {
            let soon = now.addingTimeInterval(30 * 86_400)
            let due = subscriptions.filter { $0.isActive && $0.nextPaymentDate <= soon }.sorted { $0.nextPaymentDate < $1.nextPaymentDate }
            let monthly = subscriptions.filter { $0.isActive && $0.currency == currency }
                .reduce(Decimal.zero) { $0 + $1.amount * $1.cycle.monthlyFactor }
            guard !due.isEmpty else {
                return ar ? "لا تجديدات خلال 30 يوماً. اشتراكاتك تكلّف تقريباً \(money(monthly)) شهرياً."
                          : "Nothing renews in the next 30 days. Your subscriptions cost about \(money(monthly)) a month."
            }
            let locale = GhafLocale.locale(identifier: languageCode)
            let list = due.prefix(4).map { item in
                let date = item.nextPaymentDate.formatted(.dateTime.day().month(.wide).locale(locale))
                return "• \(item.name) · \(money(item.amount, item.currency)) · \(date)"
            }.joined(separator: "\n")
            return ar ? "القادم خلال 30 يوماً:\n\(list)\nالمجموع الشهري التقريبي: \(money(monthly))."
                      : "Coming up in the next 30 days:\n\(list)\nAbout \(money(monthly)) a month in total."
        }

        let comparing = has(["compare", " vs", "versus", "more than", "less than", "than last", "قارن", "مقارنة", "أكثر من", "اكثر من", "أقل من"])
        // "more than last month" compares this month with last month, so the period is the current one.
        let periodText = comparing
            ? q.replacingOccurrences(of: "last ", with: "").replacingOccurrences(of: "الماضي", with: "")
            : q
        if has(["forecast", "predict", "expect", "end of the month", "end of month", "on track", "will i spend", "توقع", "متوقع", "نهاية الشهر"]),
           let forecast = monthForecast(transactions: transactions, currency: currency, now: now) {
            let typical = forecast.typicalMonth.map {
                ar ? " عادةً تصرف \(money($0)) في الشهر." : " You usually spend \(money($0)) a month."
            } ?? ""
            return ar ? "بهذا المعدل ستصرف تقريباً \(money(forecast.projected)) بنهاية الشهر. صرفت \(money(forecast.spentSoFar)) حتى الآن وباقي \(GhafLocalization.arabicDays(forecast.daysLeft)).\(typical)"
                      : "At this pace you'll spend about \(money(forecast.projected)) by month end. \(money(forecast.spentSoFar)) so far, \(forecast.daysLeft) days left.\(typical)"
        }

        if has(["tip", "advice", "save money", "saving", "cut back", "reduce", "نصيحة", "نصيحه", "أوفر", "اوفر", "توفير", "أقلل"]) {
            return savingTip(transactions: inCurrencyAll(transactions, currency), subscriptions: subscriptions,
                             currency: currency, languageCode: languageCode, now: now)
        }

        let period = self.period(for: periodText, now: now)
        let label = ar ? period.ar : period.en
        let inCurrency = transactions.filter { $0.currency == currency }
        let spending = inCurrency.filter { $0.isExpense && period.interval.contains($0.date) }
        let spent = spending.reduce(Decimal.zero) { $0 + $1.spendingAmount }

        // A named merchant or category narrows the question.
        if let category = matchedCategory(in: q, transactions: inCurrency, languageCode: languageCode) {
            let items = spending.filter { $0.category == category }
            let total = items.reduce(Decimal.zero) { $0 + $1.spendingAmount }
            let share = spent > 0 ? Int((NSDecimalNumber(decimal: total / spent).doubleValue * 100).rounded()) : 0
            let name = GhafLocalization.category(category, languageCode: languageCode)
            return ar ? "صرفت \(money(total)) على \(name) \(label) (\(items.count) عمليات، \(share)٪ من مصروفك)."
                      : "You spent \(money(total)) on \(name) \(label): \(items.count) transactions, \(share)% of your spending."
        }

        if let merchant = matchedMerchant(in: q, transactions: inCurrency) {
            let items = spending.filter { MerchantName.key(GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) ?? "") == merchant.key }
            let total = items.reduce(Decimal.zero) { $0 + $1.spendingAmount }
            return ar ? "صرفت \(money(total)) عند \(merchant.name) \(label) في \(items.count) عملية."
                      : "You spent \(money(total)) at \(merchant.name) \(label), across \(items.count) transactions."
        }
        // This period against the one before it.
        if comparing, let previous = period.previous {
            let before = inCurrency.filter { $0.isExpense && previous.contains($0.date) }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
            guard before > 0 else {
                return ar ? "صرفت \(money(spent)) \(label)، ولا يوجد مصروف مسجل \(period.previousAr) للمقارنة."
                          : "You spent \(money(spent)) \(label), and nothing is recorded for \(period.previousEn) to compare."
            }
            let change = Int((NSDecimalNumber(decimal: (spent - before) / before).doubleValue * 100).rounded())
            let direction = change >= 0 ? (ar ? "أكثر" : "more") : (ar ? "أقل" : "less")
            return ar ? "صرفت \(money(spent)) \(label) مقابل \(money(before)) \(period.previousAr)، أي \(abs(change))٪ \(direction)."
                      : "You spent \(money(spent)) \(label) versus \(money(before)) \(period.previousEn): \(abs(change))% \(direction)."
        }

        if has(["biggest", "largest", "most expensive", "أكبر", "أغلى", "اغلى"]) {
            guard let top = spending.max(by: { $0.spendingAmount < $1.spendingAmount }) else {
                return ar ? "لا مصاريف \(label)." : "No spending \(label)."
            }
            let date = top.date.formatted(.dateTime.day().month(.abbreviated).locale(GhafLocale.locale(identifier: languageCode)))
            let merchantName = GhafMerchantAliasStore.displayName(top.rawMerchant ?? top.merchant) ?? GhafLocalization.category(top.category, languageCode: languageCode)
            return ar ? "أكبر عملية \(label): \(merchantName) بمبلغ \(money(top.amount)) في \(date)."
                      : "Your biggest purchase \(label) was \(merchantName) for \(money(top.amount)) on \(date)."
        }

        if has(["merchant", "store", "shop", "shops", "trader", "تاجر", "التجار", "متجر", "محل"]),
           has(["most", "top", "where", "أكثر", "اكثر", "وين", "أين"]) {
            let grouped = Dictionary(grouping: spending.filter { !(GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) ?? "").isEmpty }) {
                MerchantName.key(GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) ?? "")
            }
            let rows = grouped.values.map { items -> (String, Decimal) in
                (GhafMerchantAliasStore.displayName(items[0].rawMerchant ?? items[0].merchant) ?? "", items.reduce(Decimal.zero) { $0 + $1.spendingAmount })
            }.sorted { $0.1 > $1.1 }.prefix(4)
            guard !rows.isEmpty else { return ar ? "لا توجد متاجر مسجلة \(label)." : "No merchants are recorded \(label)." }
            let list = rows.map { "• \($0.0) · \(money($0.1))" }.joined(separator: "\n")
            return ar ? "أكثر المتاجر إنفاقاً \(label):\n\(list)\nإجمالي المصروف: \(money(spent))."
                      : "Top merchants \(label):\n\(list)\nTotal spending: \(money(spent))."
        }

        if has(["income", "earn", "salary", "received", "دخل", "راتب", "استلمت"]) {
            let income = inCurrency.filter { period.interval.contains($0.date) }.reduce(Decimal.zero) { $0 + $1.incomeAmount }
            let net = income - spent
            return ar ? "دخلك \(label) \(money(income))، ومصروفك \(money(spent))، والصافي \(money(net))."
                      : "Income \(label) is \(money(income)) against \(money(spent)) spent, a net of \(money(net))."
        }

        if has(["where", "most", "top", "categor", "breakdown", "chart", "graph", "وين", "أكثر", "اكثر", "فئة", "فئات", "رسم"]) {
            let byCategory = Dictionary(grouping: spending, by: \.category)
                .mapValues { $0.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
                .filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(3)
            guard spent > 0, !byCategory.isEmpty else { return ar ? "لا مصاريف \(label) بعد." : "No spending \(label) yet." }
            let parts = byCategory.map { item -> String in
                let share = Int((NSDecimalNumber(decimal: item.value / spent).doubleValue * 100).rounded())
                return "• \(GhafLocalization.category(item.key, languageCode: languageCode)) · \(money(item.value)) · \(share)%"
            }.joined(separator: "\n")
            return ar ? "أعلى الفئات \(label):\n\(parts)\nإجمالي المصروف: \(money(spent))."
                      : "Top categories \(label):\n\(parts)\nTotal spending: \(money(spent))."
        }

        if has(["spen", "spent", "cost", "صرف", "مصروف", "دفعت", "كم"]) {
            guard spent > 0 else { return ar ? "ما سجلت أي مصروف \(label)." : "You haven't spent anything \(label)." }
            let days = max(1, Calendar.current.dateComponents([.day], from: period.interval.start, to: min(now, period.interval.end)).day ?? 1)
            let top = Dictionary(grouping: spending, by: \.category).mapValues { $0.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
                .max { $0.value < $1.value }
            let topName = top.map { GhafLocalization.category($0.key, languageCode: languageCode) } ?? ""
            return ar ? "صرفت \(money(spent)) \(label) في \(spending.count) عملية، بمعدل \(money(spent / Decimal(days))) يومياً. أكثر فئة: \(topName)."
                      : "You spent \(money(spent)) \(label) over \(spending.count) transactions, about \(money(spent / Decimal(days))) a day. Top category: \(topName)."
        }
        return nil
    }

    private static func inCurrencyAll(_ transactions: [GhafTransaction], _ currency: String) -> [GhafTransaction] {
        transactions.filter { $0.currency == currency }
    }

    /// One concrete suggestion from the numbers: the category that grew most against the usual month,
    /// else the largest category, plus what trimming it would save.
    static func savingTip(transactions: [GhafTransaction], subscriptions: [GhafSubscription],
                          currency: String, languageCode: String, now: Date) -> String {
        let ar = languageCode == "ar"
        let calendar = GhafCalendar.current
        func money(_ value: Decimal) -> String { GhafFormat.money(value, currency: currency, languageCode: languageCode) }
        func byCategory(_ interval: DateInterval?) -> [String: Decimal] {
            guard let interval else { return [:] }
            return Dictionary(grouping: transactions.filter { $0.isExpense && interval.contains($0.date) }, by: \.category)
                .mapValues { $0.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
        }
        let thisMonth = byCategory(calendar.dateInterval(of: .month, for: now))
        var usual: [String: Decimal] = [:]
        for offset in 1...3 {
            let date = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            for (category, value) in byCategory(calendar.dateInterval(of: .month, for: date)) { usual[category, default: 0] += value / 3 }
        }
        let grown = thisMonth.compactMap { category, value -> (String, Decimal, Decimal)? in
            guard let base = usual[category], base > 0, value > base * Decimal(1.25) else { return nil }
            return (category, value, base)
        }.max { ($0.1 - $0.2) < ($1.1 - $1.2) }
        if let (category, value, base) = grown {
            let name = GhafLocalization.category(category, languageCode: languageCode)
            return ar ? "\(name) أعلى من المعتاد هذا الشهر: \(money(value)) مقابل \(money(base)) عادةً. لو رجعت لمعدلك المعتاد توفّر \(money(value - base))."
                      : "\(name) is running high: \(money(value)) this month against a usual \(money(base)). Getting back to normal saves \(money(value - base))."
        }
        if let top = thisMonth.filter({ $0.value > 0 }).max(by: { $0.value < $1.value }) {
            let name = GhafLocalization.category(top.key, languageCode: languageCode)
            return ar ? "أكبر فئة عندك \(name) بـ \(money(top.value)) هذا الشهر. تقليلها 10٪ يوفّر \(money(top.value / 10)) شهرياً."
                      : "Your biggest category is \(name) at \(money(top.value)) this month. Trimming it by 10% saves \(money(top.value / 10)) a month."
        }
        let monthly = subscriptions.filter { $0.isActive && $0.currency == currency }.reduce(Decimal.zero) { $0 + $1.amount * $1.cycle.monthlyFactor }
        return ar ? "لا مصاريف كافية هذا الشهر لنصيحة. اشتراكاتك تكلّف \(money(monthly)) شهرياً؛ راجع ما لا تستخدمه."
                  : "Not enough spending this month for a tip yet. Your subscriptions cost \(money(monthly)) a month; check for any you don't use."
    }

    /// This month's projected spending in `currency`, using the three complete months before it as history.
    static func monthForecast(transactions: [GhafTransaction], currency: String, now: Date = .now) -> SpendingInsights.Forecast? {
        let calendar = GhafCalendar.current
        guard let month = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
        let spending = transactions.filter { $0.currency == currency && $0.isExpense }
        func total(_ interval: DateInterval) -> Decimal {
            spending.filter { interval.contains($0.date) }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        }
        let past = (1...3).compactMap { offset -> Decimal? in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now),
                  let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
            return total(interval)
        }
        let spent = total(DateInterval(start: month.start, end: now))
        return SpendingInsights.forecast(spentSoFar: spent, day: calendar.component(.day, from: now),
                                         daysInMonth: days, pastMonthTotals: past)
    }

    static func period(for q: String, now: Date) -> Period {
        let calendar = GhafCalendar.current
        func window(_ component: Calendar.Component, _ offset: Int) -> DateInterval {
            let date = calendar.date(byAdding: component, value: offset, to: now) ?? now
            return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: now, duration: 86_400)
        }
        if q.contains("yesterday") || q.contains("أمس") || q.contains("امس") {
            return Period(interval: window(.day, -1), previous: window(.day, -2), en: "yesterday", ar: "أمس",
                          previousEn: "the day before", previousAr: "اليوم الذي قبله")
        }
        if q.contains("today") || q.contains("اليوم") {
            return Period(interval: window(.day, 0), previous: window(.day, -1), en: "today", ar: "اليوم",
                          previousEn: "yesterday", previousAr: "أمس")
        }
        if q.contains("last week") || q.contains("الأسبوع الماضي") || q.contains("الاسبوع الماضي") {
            return Period(interval: window(.weekOfYear, -1), previous: window(.weekOfYear, -2), en: "last week", ar: "الأسبوع الماضي",
                          previousEn: "the week before", previousAr: "الأسبوع الذي قبله")
        }
        if q.contains("week") || q.contains("أسبوع") || q.contains("اسبوع") {
            return Period(interval: window(.weekOfYear, 0), previous: window(.weekOfYear, -1), en: "this week", ar: "هذا الأسبوع",
                          previousEn: "last week", previousAr: "الأسبوع الماضي")
        }
        if q.contains("last month") || q.contains("الشهر الماضي") {
            return Period(interval: window(.month, -1), previous: window(.month, -2), en: "last month", ar: "الشهر الماضي",
                          previousEn: "the month before", previousAr: "الشهر الذي قبله")
        }
        if q.contains("year") || q.contains("سنة") || q.contains("السنه") {
            return Period(interval: window(.year, 0), previous: window(.year, -1), en: "this year", ar: "هذه السنة",
                          previousEn: "last year", previousAr: "السنة الماضية")
        }
        return Period(interval: window(.month, 0), previous: window(.month, -1), en: "this month", ar: "هذا الشهر",
                      previousEn: "last month", previousAr: "الشهر الماضي")
    }

    /// A merchant the user has paid before whose name appears in the question.
    static func matchedMerchant(in q: String, transactions: [GhafTransaction]) -> (key: String, name: String)? {
        var seen: [String: String] = [:]
        for item in transactions where item.isExpense {
            guard let name = GhafMerchantAliasStore.displayName(item.rawMerchant ?? item.merchant) else { continue }
            let key = MerchantName.key(name)
            if key.count >= 3, seen[key] == nil { seen[key] = name }
        }
        // Whole words only, so a merchant called "Tip" doesn't match "tips".
        let text = " " + MerchantName.key(q) + " "
        // Longest names first so "careem food" wins over "careem".
        return seen.sorted { $0.key.count > $1.key.count }
            .first { text.contains(" \($0.key) ") }
            .map { (key: $0.key, name: $0.value) }
    }

    static func matchedCategory(in q: String, transactions: [GhafTransaction], languageCode: String) -> String? {
        let categories = Set(transactions.filter(\.isExpense).map(\.category))
        return categories.sorted { $0.count > $1.count }.first { category in
            let names = [category.lowercased(), GhafLocalization.category(category, languageCode: "ar")]
            // "restaurants" also matches "restaurant".
            return names.contains { name in
                name.count >= 3 && (q.contains(name) || (name.count >= 5 && q.contains(String(name.dropLast()))))
            }
        }
    }
}
