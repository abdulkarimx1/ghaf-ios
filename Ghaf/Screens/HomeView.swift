import SwiftUI
import SwiftData
import GhafCore
import AppIntents

struct GhafHomeView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(GhafTabRouter.self) private var router

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]
    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]

    @State private var showQuickAdd = false
    @State private var showVoiceEntry = false
    @State private var showAutomationGuide = false
    @State private var showSalaryCheckIn = false
    @State private var showAccounts = false
    @State private var showInsights = false
    @State private var showReview = false
    @State private var selectedTransaction: GhafTransaction?
    @AppStorage(GhafAutomationStatus.lastRunKey) private var automationLastRun: Double = 0
    /// Observed so the weekly figures redraw as soon as the week start changes.
    @AppStorage(GhafCalendar.weekStartKey) private var weekStart = 0
    @AppStorage("ghaf.hideBalances") private var hideBalances = false
    @State private var activityPeriodIndex = 0

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    /// Everything Home shows, derived in one pass per render instead of once per view.
    private struct Summary {
        var accountBalances: [UUID: Decimal] = [:]
        var balances: [GhafCurrencyBalance] = []
        var mainCurrency = ""
        var spent: Decimal = 0
        var income: Decimal = 0
        var count = 0
        var topCategory: (name: String, amount: Decimal)?
        var reviewCount = 0
    }

    private func makeSummary() -> Summary {
        var summary = Summary()
        summary.accountBalances = GhafAccountBalanceCalculator.balances(accounts: accounts, transactions: transactions)
        summary.balances = GhafAccountBalanceCalculator.balancesByCurrency(accounts: accounts, balances: summary.accountBalances)
        let main = summary.balances.contains { $0.currency == settings.currency }
            ? settings.currency : (summary.balances.first?.currency ?? settings.currency)
        summary.mainCurrency = main

        let calendar = GhafCalendar.current
        let component: Calendar.Component = [.day, .weekOfYear, .month][activityPeriodIndex]
        let interval = calendar.dateInterval(of: component, for: .now)
        var byCategory: [String: Decimal] = [:]
        for transaction in transactions {
            if transaction.needsReview { summary.reviewCount += 1 }
            guard let interval else { continue }
            let date = transaction.date
            if date >= interval.end { continue }
            if date < interval.start { continue }
            summary.count += 1
            guard transaction.currency == main, transaction.isSpendingOrIncome else { continue }
            if transaction.isExpense {
                summary.spent += transaction.spendingAmount
                byCategory[transaction.category, default: 0] += transaction.spendingAmount
            } else if transaction.isIncome {
                summary.income += transaction.amount
            }
        }
        if let top = byCategory.max(by: { $0.value < $1.value }), top.value > 0 { summary.topCategory = (top.key, top.value) }
        return summary
    }

    var body: some View {
        let summary = makeSummary()
        NavigationStack {
            ScrollView {
                VStack(spacing: GhafMetrics.sectionSpacing) {
                    header.ghafEntrance(0)
                    balanceCard(summary).ghafEntrance(1)
                    actionRow(summary).ghafEntrance(2)
                    insightCard(summary).ghafEntrance(3)
                    recentActivity.ghafEntrance(4)
                }
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ghafBackground(theme: theme)
            .onChange(of: router.homeReselects) { _, _ in
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { activityPeriodIndex = (activityPeriodIndex + 1) % 3 }
            }
            .sensoryFeedback(.selection, trigger: activityPeriodIndex)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showAccounts) { GhafAccountsView(settings: settings) }
            .sheet(isPresented: $showQuickAdd) { GhafQuickAddView(settings: settings) }
            .sheet(isPresented: $showVoiceEntry) {
                NavigationStack { GhafVoiceEntryView(settings: settings) }
            }
            .sheet(isPresented: $showInsights) {
                GhafInsightsView(settings: settings).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReview) {
                GhafReviewInboxView(settings: settings).presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedTransaction) { transaction in
                GhafTransactionDetailView(transaction: transaction, settings: settings, accounts: accounts.filter { !$0.isArchived })
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAutomationGuide) {
                NavigationStack {
                    GhafAutomationGuideView(settings: settings)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(ar ? "تم" : "Done") { showAutomationGuide = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSalaryCheckIn) {
                GhafSalaryCheckInView(settings: settings, accounts: accounts)
            }
            .onAppear(perform: checkSalaryDue)
            .task {
                if settings.salaryEnabled == true, settings.salaryReminderEnabled == true,
                   let day = settings.salaryDay {
                    try? await GhafSalaryReminderService.scheduleNext(salaryDay: day, languageCode: settings.languageCode)
                }
            }
        }
    }

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }

    // MARK: Header: greeting, accounts pill, hide-balances eye

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(settings.userName.isEmpty ? (ar ? "غاف" : "Ghaf") : settings.userName)
                    .font(GhafTypography.heading(24, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Button { showAccounts = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.bifold.fill").font(.system(size: 13, weight: .bold))
                    Text(ar ? "الحسابات" : "Accounts")
                        .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                    Image(systemName: "chevron.forward").font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14).frame(height: 40)
                .background(theme.surface, in: Capsule())
                .shadow(color: theme.shadow, radius: 8, y: 3)
            }
            .buttonStyle(.ghafPress)
            Button {
                withAnimation(.snappy(duration: 0.22)) { hideBalances.toggle() }
            } label: {
                Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
                    .shadow(color: theme.shadow, radius: 8, y: 3)
            }
            .buttonStyle(.ghafPress)
            .sensoryFeedback(.selection, trigger: hideBalances)
            .accessibilityLabel(ar ? (hideBalances ? "إظهار الأرصدة" : "إخفاء الأرصدة")
                                   : (hideBalances ? "Show balances" : "Hide balances"))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if ar { return hour < 12 ? "صباح الخير" : "مساء الخير" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: Balance card: tap to switch Day / Week / Month

    private var periodName: String {
        ar ? ["اليوم", "هذا الأسبوع", "هذا الشهر"][activityPeriodIndex]
           : ["Today", "This week", "This month"][activityPeriodIndex]
    }

    private func balanceCard(_ summary: Summary) -> some View {
        let main = summary.balances.first { $0.currency == summary.mainCurrency }
        let others = summary.balances.filter { $0.currency != summary.mainCurrency }

        return VStack(spacing: 14) {
            Text(ar ? "إجمالي الرصيد" : "Total balance")
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)

            GhafMoneyLabel(amount: main?.amount ?? 0, currency: summary.mainCurrency,
                           languageCode: lang, size: 44, hidden: hideBalances)
                .foregroundStyle(theme.primaryText)

            // Other currencies are listed, never added to the main total.
            ForEach(others) { balance in
                GhafMoneyLabel(amount: balance.amount, currency: balance.currency,
                               languageCode: lang, size: 16, hidden: hideBalances)
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 14) {
                changeLine(icon: "arrow.down.right", value: summary.spent, color: theme.debit,
                           label: ar ? "صرفت" : "spent", currency: summary.mainCurrency)
                changeLine(icon: "arrow.up.right", value: summary.income, color: theme.credit,
                           label: ar ? "دخل" : "in", currency: summary.mainCurrency)
            }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == activityPeriodIndex ? theme.accent : theme.secondaryText.opacity(0.25))
                        .frame(width: index == activityPeriodIndex ? 18 : 6, height: 6)
                }
                Text(periodName + " · \(summary.count) " + (ar ? "عملية" : (summary.count == 1 ? "transaction" : "transactions")))
                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .contentTransition(.numericText())
            }

            accountStrip(summary)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .ghafCard(theme: theme, radius: 28)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.25)) { activityPeriodIndex = (activityPeriodIndex + 1) % 3 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(ar ? "اضغط للتبديل بين اليوم والأسبوع والشهر" : "Tap to switch between day, week and month")
        .sensoryFeedback(.selection, trigger: activityPeriodIndex)
    }

    private func changeLine(icon: String, value: Decimal, color: Color, label: String, currency: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .heavy))
            GhafMoneyLabel(amount: value, currency: currency, languageCode: lang, size: 14, hidden: hideBalances)
            Text(label).font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func accountStrip(_ summary: Summary) -> some View {
        let open = accounts.filter { !$0.isArchived }
        if !open.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(open) { account in
                        Button { showAccounts = true } label: {
                            VStack(spacing: 2) {
                                Text(account.name)
                                    .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText)
                                GhafMoneyLabel(amount: summary.accountBalances[account.id] ?? account.openingBalance,
                                               currency: account.currency, languageCode: lang,
                                               size: 14, hidden: hideBalances)
                                    .foregroundStyle(theme.primaryText)
                            }
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.ghafPress)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Big pill actions

    private func actionRow(_ summary: Summary) -> some View {
        HStack(spacing: 10) {
            GhafPillButton(title: ar ? "إضافة" : "Add", icon: "plus", theme: theme, languageCode: lang,
                           prominent: true) { showQuickAdd = true }
            GhafPillButton(title: ar ? "بالصوت" : "Say it", icon: "mic.fill", theme: theme,
                           languageCode: lang) { showVoiceEntry = true }
            GhafPillButton(title: ar ? "مراجعة" : "Review", icon: "tray.full.fill", theme: theme,
                           languageCode: lang, badge: summary.reviewCount) { showReview = true }
        }
    }

    // MARK: Dark insight card

    private func insightCard(_ summary: Summary) -> some View {
        Button { showInsights = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(ar ? "التحليلات" : "Insights", systemImage: "chart.pie.fill")
                        .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.inkText.opacity(0.75))
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(theme.inkText)
                        .frame(width: 34, height: 34)
                        .background(theme.inkText.opacity(0.12), in: Circle())
                }
                GhafMoneyText.text(insightText(summary), size: 19)
                    .id(activityPeriodIndex)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .font(GhafTypography.heading(19, languageCode: lang))
                    .foregroundStyle(theme.inkText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if summary.spent + summary.income > 0 {
                    // Share of money in vs out for the selected period.
                    GeometryReader { proxy in
                        let total = NSDecimalNumber(decimal: summary.spent + summary.income).doubleValue
                        let share = NSDecimalNumber(decimal: summary.spent).doubleValue / total
                        HStack(spacing: 4) {
                            Capsule().fill(theme.inkDebit).frame(width: max(6, (proxy.size.width - 4) * share))
                            Capsule().fill(theme.inkCredit)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.ink, in: RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.ghafPress)
    }

    private func insightText(_ summary: Summary) -> String {
        guard let top = summary.topCategory, summary.spent > 0 else {
            return ar ? "ما صرفت شيئاً \(periodName) بعد. يوم جميل لمحفظتك."
                      : "Nothing spent \(periodName.lowercased()) yet. A good day for your wallet."
        }
        let category = GhafLocalization.category(top.name, languageCode: lang)
        let share = Int((NSDecimalNumber(decimal: top.amount / summary.spent).doubleValue * 100).rounded())
        guard !hideBalances else {
            return ar ? "\(category) أكبر مصروفك \(periodName)، \(share)٪ من الإجمالي."
                      : "\(category) is your biggest spend \(periodName.lowercased()), \(share)% of the total."
        }
        let amount = GhafFormat.money(top.amount, currency: summary.mainCurrency, languageCode: lang)
        return ar ? "\(category) أكبر مصروفك \(periodName): \(amount)، أي \(share)٪ من الإجمالي."
                  : "\(category) is your biggest spend \(periodName.lowercased()): \(amount), \(share)% of the total."
    }

    // MARK: Recent activity (a short shortcut; the full list lives in Transactions)

    private var recentActivity: some View {
        VStack(spacing: 10) {
            GhafSectionHeader(title: ar ? "النشاط" : "Activity", theme: theme, languageCode: lang,
                              actionTitle: ar ? "عرض الكل" : "See all") { router.selectedTab = 3 }
            VStack(spacing: 0) {
                let recent = Array(transactions.prefix(4))
                if recent.isEmpty && automationLastRun == 0 {
                    GhafListRow(icon: "bolt.fill", tint: theme.accent,
                                title: ar ? "اربط رسائل البنك" : "Connect your bank messages",
                                subtitle: ar ? "سجّل العمليات تلقائياً عبر الاختصارات" : "Log transactions automatically with Shortcuts",
                                theme: theme, languageCode: lang, chevron: true)
                        .onTapGesture { showAutomationGuide = true }
                } else {
                    ForEach(recent) { transaction in
                        Button { selectedTransaction = transaction } label: {
                            GhafTransactionRow(transaction: transaction, theme: theme, languageCode: lang, hidden: hideBalances)
                        }
                        .buttonStyle(.ghafPress)
                        if transaction.id != recent.last?.id {
                            Divider().overlay(theme.outline).padding(.leading, 58)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .ghafCard(theme: theme)

            if automationLastRun == 0 {
            Button { showAutomationGuide = true } label: {
                GhafListRow(icon: "bolt.fill", tint: theme.accent,
                            title: ar ? "ربط البنك" : "Bank setup",
                            subtitle: ar ? "التقاط العمليات من رسائل البنك" : "Capture transactions from bank messages",
                            theme: theme, languageCode: lang, chevron: true)
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .ghafCard(theme: theme)
            }
            .buttonStyle(.ghafPress)
            }
        }
    }

    private func checkSalaryDue() {
        guard settings.salaryEnabled == true,
              let salaryDay = settings.salaryDay,
              let range = Calendar.current.range(of: .day, in: .month, for: .now) else {
            return
        }

        let effectiveDay = min(max(salaryDay, 1), range.count)
        let currentDay = Calendar.current.component(.day, from: .now)
        let key = GhafSalaryCycle.periodKey(for: .now, salaryDay: salaryDay)

        if currentDay >= effectiveDay && settings.lastSalaryDecisionKey != key {
            showSalaryCheckIn = true
        }
    }
}

// MARK: - Transaction Row

struct GhafTransactionRow: View {
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String
    var hidden = false

    var body: some View {
        HStack(spacing: 14) {
            GhafCategoryIcon(category: transaction.category, tint: theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(merchantTitle)
                    .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(GhafLocalization.category(transaction.category, languageCode: languageCode)
                         + (transaction.subcategory.map { " · \($0)" } ?? ""))
                    Text("·")
                    Text(transaction.date.formatted(
                        .dateTime.hour().minute().locale(Locale(identifier: languageCode))
                    ))
                }
                .font(GhafTypography.body(13, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 2) {
                    Text(transaction.direction == "credit" ? "+" : "−")
                        .font(GhafTypography.number(16, weight: .bold))
                    GhafMoneyLabel(amount: transaction.amount, currency: transaction.currency, languageCode: languageCode, size: 16, hidden: hidden)
                }
                .foregroundStyle(transaction.direction == "credit" ? theme.credit : theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)

                if transaction.needsReview {
                    Text(languageCode == "ar" ? "مراجعة" : "REVIEW")
                        .font(GhafTypography.body(11, languageCode: languageCode, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.close)
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var merchantTitle: String {
        if let merchant = transaction.merchant, !merchant.isEmpty {
            return merchant
        }
        return GhafLocalization.category(transaction.category, languageCode: languageCode)
    }

}

// MARK: - Manual Transaction Entry

struct GhafQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]

    let settings: GhafSettings

    @State private var selectedAccountID: UUID?
    @State private var amount = ""
    @State private var merchant = ""
    @State private var category = "Other"
    @State private var direction = "debit"
    @State private var note = ""
    @State private var date = Date()
    @State private var errorMessage = ""

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(settings.languageCode == "ar" ? "عملية جديدة" : "New transaction")
                        .font(GhafTypography.display(30, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)

                    NavigationLink {
                        GhafVoiceEntryView(settings: settings)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .semibold))
                            Text(settings.languageCode == "ar" ? "أضف بالصوت" : "Add with voice")
                                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                            Spacer()
                            Image(systemName: settings.languageCode == "ar" ? "arrow.up.left" : "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(theme.accent)
                        .padding(14)
                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.ghafPress)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(settings.languageCode == "ar" ? "المبلغ" : "AMOUNT")
                            .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(theme.secondaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(GhafFormat.symbol(for: settings.currency, languageCode: settings.languageCode))
                                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                            TextField("0.00", text: $amount)
                                .font(GhafTypography.number(34, weight: .bold))
                                .keyboardType(.decimalPad)
                                .foregroundStyle(theme.primaryText)
                        }
                        .padding(16)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    fieldLabel(settings.languageCode == "ar" ? "المتجر" : "Merchant")
                    styledField(settings.languageCode == "ar" ? "اسم المتجر أو الجهة" : "Merchant or store", text: $merchant)

                    fieldLabel(settings.languageCode == "ar" ? "النوع" : "Type")
                    Picker(settings.languageCode == "ar" ? "النوع" : "Type", selection: $direction) {
                        Text(settings.languageCode == "ar" ? "مصروف" : "Expense").tag("debit")
                        Text(settings.languageCode == "ar" ? "دخل" : "Income").tag("credit")
                    }
                    .pickerStyle(.segmented)

                    fieldLabel(settings.languageCode == "ar" ? "الفئة" : "Category")
                    Picker(settings.languageCode == "ar" ? "الفئة" : "Category", selection: $category) {
                        ForEach(settings.categories, id: \.self) { Text(GhafLocalization.category($0, languageCode: settings.languageCode)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accent)

                    fieldLabel(settings.languageCode == "ar" ? "الحساب" : "Account")
                    Picker(settings.languageCode == "ar" ? "الحساب" : "Account", selection: $selectedAccountID) {
                        ForEach(accounts.filter { !$0.isArchived }, id: \.id) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accent)

                    fieldLabel(settings.languageCode == "ar" ? "التاريخ" : "Date")
                    DatePicker(settings.languageCode == "ar" ? "التاريخ" : "Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .tint(theme.accent)

                    fieldLabel(settings.languageCode == "ar" ? "ملاحظة" : "Note")
                    styledField(settings.languageCode == "ar" ? "ملاحظة اختيارية" : "Optional note", text: $note)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(GhafTypography.body(13, languageCode: settings.languageCode))
                            .foregroundStyle(theme.over)
                    }

                    Button(settings.languageCode == "ar" ? "حفظ العملية" : "Save transaction", action: save)
                        .ghafProminentButton(theme: theme, languageCode: settings.languageCode)
                }
                .padding(22)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .ghafKeyboardDone()
            .navigationTitle(settings.languageCode == "ar" ? "إضافة" : "Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.languageCode == "ar" ? "إلغاء" : "Cancel") { dismiss() }
                }
            }
        }
        .tint(theme.accent)
        .onAppear {
            selectedAccountID = accounts.first(where: { $0.isPrimary && !$0.isArchived })?.id
                ?? accounts.first(where: { !$0.isArchived })?.id
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.secondaryText)
    }

    private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(GhafTypography.body(15, languageCode: settings.languageCode))
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline, lineWidth: 1))
    }

    private func save() {
        guard let value = Decimal(string: amount), value > 0 else {
            errorMessage = settings.languageCode == "ar" ? "أدخل مبلغاً صحيحاً." : "Enter a valid amount."
            return
        }

        let selectedAccount = accounts.first(where: { $0.id == selectedAccountID })
        let transactionDirection = TransactionDirection(rawValue: direction) ?? .debit
        let suggestedCategory = (try? MerchantCategorizer.category(
            for: merchant.isEmpty ? nil : merchant,
            direction: transactionDirection,
            context: modelContext
        )) ?? "Other"
        let finalCategory = category == "Other" ? suggestedCategory : category

        let parsed = ParsedTransaction(
            amount: value,
            currency: selectedAccount?.currency ?? settings.currency,
            merchant: merchant.isEmpty ? nil : merchant,
            date: date,
            direction: transactionDirection,
            confidence: 1.0,
            bank: nil
        )

        let transaction = GhafTransaction(
            fingerprint: "manual-\(UUID().uuidString)",
            parsed: parsed,
            category: finalCategory,
            needsReview: false,
            isReversal: false,
            accountID: selectedAccountID
        )
        transaction.note = note
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = settings.languageCode == "ar" ? "تعذر حفظ العملية." : "Could not save transaction."
        }
    }
}
