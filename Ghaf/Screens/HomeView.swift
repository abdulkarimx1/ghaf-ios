import SwiftUI
import SwiftData
import GhafCore
import AppIntents

struct GhafHomeView: View {
    @Environment(\.colorScheme) private var systemColorScheme

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
    @State private var hideBalances = false
    @State private var activityPeriodIndex = 0

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var snapshot: BudgetSnapshot {
        BudgetCalculator.snapshot(settings: settings, transactions: transactions)
    }

    private var activityTransactions: [GhafTransaction] {
        let calendar = Calendar.current
        let now = Date()
        switch activityPeriodIndex {
        case 1:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return transactions.filter { $0.date >= interval.start && $0.date < interval.end }
        case 2:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
            return transactions.filter { $0.date >= interval.start && $0.date < interval.end }
        default:
            return transactions.filter { calendar.isDate($0.date, inSameDayAs: now) }
        }
    }

    private var activityPeriodTitle: String {
        if settings.languageCode == "ar" {
            return ["حركة اليوم", "حركة الأسبوع", "حركة الشهر"][activityPeriodIndex]
        }
        return ["Today", "This week", "This month"][activityPeriodIndex]
    }

    private var activityTotal: Decimal {
        activityTransactions
            .filter { $0.currency == settings.currency && $0.direction == "debit" }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                header
                heroCard
                actionGrid
                todaySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ghafBackground(theme: theme)
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

    // MARK: Hero: total balance + what is left to spend

    private var heroCard: some View {
        let totals = GhafAccountBalanceCalculator.balancesByCurrency(accounts: accounts, transactions: transactions)
        let main = totals.first(where: { $0.currency == settings.currency }) ?? totals.first
        let currency = main?.currency ?? settings.currency

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ar ? "رصيدك" : "YOUR BALANCE")
                    .font(GhafTypography.body(ar ? 14 : 11, languageCode: settings.languageCode, weight: .bold))
                    .tracking(ar ? 0 : 1.6)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) { hideBalances.toggle() }
                } label: {
                    Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ar ? (hideBalances ? "إظهار الأرصدة" : "إخفاء الأرصدة")
                                       : (hideBalances ? "Show balances" : "Hide balances"))
            }
            .foregroundStyle(theme.accentContrast.opacity(0.8))

            HStack(spacing: 10) {
                GhafCurrencyIcon(currency: currency, size: 28)
                Text(hideBalances ? "••••••" : GhafFormat.money(main?.amount ?? 0, currency: currency, languageCode: settings.languageCode))
                    .font(GhafTypography.number(44, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(theme.accentContrast)

            HStack(spacing: 8) {
                Text(snapshot.hasBudget
                     ? (ar ? "المتبقي للصرف" : "Left to spend") + " · " + GhafFormat.money(snapshot.remaining, currency: settings.currency, languageCode: settings.languageCode)
                     : (ar ? "حدد دخلك الشهري في المزيد" : "Set your monthly income in More"))
                    .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if totals.count > 1 {
                    Text("+\(totals.count - 1)")
                        .font(GhafTypography.number(13, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(theme.accentContrast.opacity(0.15), in: Capsule())
                }
            }
            .foregroundStyle(theme.accentContrast.opacity(0.9))

            if snapshot.hasBudget {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.accentContrast.opacity(0.18))
                        Capsule().fill(theme.accentContrast)
                            .frame(width: geometry.size.width * min(max(snapshot.progress, 0), 1))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Big action buttons (2 x 3, no scrolling)

    private var actionGrid: some View {
        let reviewCount = transactions.filter(\.needsReview).count
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                actionTile(ar ? "إضافة مصروف" : "Add expense", icon: "plus", filled: true) { showQuickAdd = true }
                actionTile(ar ? "بالصوت" : "Say it", icon: "mic.fill", filled: true) { showVoiceEntry = true }
            }
            GridRow {
                actionTile(ar ? "الحسابات" : "Accounts", icon: "wallet.bifold.fill") { showAccounts = true }
                actionTile(ar ? "التحليلات" : "Insights", icon: "chart.pie.fill") { showInsights = true }
            }
            GridRow {
                actionTile(ar ? "للمراجعة" : "To review", icon: "tray.full.fill", badge: reviewCount) { showReview = true }
                actionTile(ar ? "ربط البنك" : "Bank setup", icon: "bolt.fill") { showAutomationGuide = true }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func actionTile(_ title: String, icon: String, filled: Bool = false, badge: Int = 0,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                    Spacer()
                    if badge > 0 {
                        Text("\(badge)")
                            .font(GhafTypography.number(14, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.red, in: Capsule())
                    }
                }
                Spacer(minLength: 8)
                Text(title)
                    .font(GhafTypography.body(18, languageCode: settings.languageCode, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(filled ? theme.accentContrast : theme.primaryText)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .leading)
            .background(filled ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(filled ? .clear : theme.outline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(settings.languageCode == "ar" ? greeting : greeting.uppercased())
                    .font(GhafTypography.heading(settings.languageCode == "ar" ? 18 : 11, languageCode: settings.languageCode))
                    .tracking(settings.languageCode == "ar" ? 0 : 1.8)
                    .foregroundStyle(theme.secondaryText)

                Text(settings.languageCode == "ar"
                     ? (settings.userName.isEmpty ? "أموالك بوضوح" : "مرحباً، \(settings.userName)")
                     : (settings.userName.isEmpty ? "Your money, in view." : "Hello, \(settings.userName)."))
                    .font(GhafTypography.display(30, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Date.now.formatted(
                    .dateTime.weekday(.wide).month(.abbreviated).day()
                    .locale(Locale(identifier: settings.languageCode))
                ))
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 4)

            ZStack {
                Circle().fill(theme.accent.opacity(0.12))
                GhafTreeMark(color: theme.accent).padding(11)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if settings.languageCode == "ar" {
            return hour < 17 ? "صـبـاح الخـير" : "مسـاء الخـير"
        }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var todaySection: some View {
        Button {
            activityPeriodIndex = (activityPeriodIndex + 1) % 3
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activityPeriodTitle)
                        .font(GhafTypography.heading(16, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(settings.languageCode == "ar" ? "\(activityTransactions.count) عملية" : "\(activityTransactions.count) transactions")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 8)
                Text(GhafFormat.money(activityTotal, currency: settings.currency, languageCode: settings.languageCode))
                    .font(GhafTypography.number(16, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Image(systemName: "arrow.2.circlepath").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .ghafCard(theme: theme, radius: 17)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.languageCode == "ar" ? "تغيير فترة عرض العمليات" : "Change activity period")
        .accessibilityHint(settings.languageCode == "ar" ? "اضغط للتبديل بين اليوم والأسبوع والشهر." : "Tap to cycle between day, week and month.")
    }

}

// MARK: - Transaction Row

struct GhafTransactionRow: View {
    let transaction: GhafTransaction
    let theme: GhafTheme
    let languageCode: String

    var body: some View {
        HStack(spacing: 12) {
            GhafCategoryIcon(category: transaction.category, tint: theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(merchantTitle)
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(GhafLocalization.category(transaction.category, languageCode: languageCode))
                    Text("·")
                    Text(transaction.date.formatted(
                        .dateTime.hour().minute().locale(Locale(identifier: languageCode))
                    ))
                }
                .font(GhafTypography.body(11, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(amountText)
                    .font(GhafTypography.number(14, weight: .semibold))
                    .foregroundStyle(transaction.direction == "credit" ? theme.credit : theme.primaryText)
                    .lineLimit(1)

                if transaction.needsReview {
                    Text(languageCode == "ar" ? "مراجعة" : "REVIEW")
                        .font(GhafTypography.body(9, languageCode: languageCode, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.close)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var merchantTitle: String {
        if let merchant = transaction.merchant, !merchant.isEmpty {
            return merchant
        }
        return GhafLocalization.category(transaction.category, languageCode: languageCode)
    }

    private var amountText: String {
        let prefix = transaction.direction == "credit" ? "+" : "−"
        return prefix + GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: languageCode)
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
                    .buttonStyle(.plain)

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
