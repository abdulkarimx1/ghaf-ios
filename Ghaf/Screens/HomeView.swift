import SwiftUI
import SwiftData
import GhafCore
import AppIntents

struct GhafHomeView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @State private var showQuickAdd = false
    @State private var showAutomationGuide = false

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

    private var todayTransactions: [GhafTransaction] {
        transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    budgetCard
                    automationCard
                    manualEntryButton
                    todaySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQuickAdd) {
                GhafQuickAddView(settings: settings)
            }
            .sheet(isPresented: $showAutomationGuide) {
                NavigationStack {
                    GhafAutomationGuideView(settings: settings)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showAutomationGuide = false }
                            }
                        }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting.uppercased())
                    .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.secondaryText)

                Text(settings.userName.isEmpty ? "Your money, in view." : "Hello, \(settings.userName).")
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
                Circle().fill(theme.accent.opacity(0.10))
                GhafTreeMark(color: theme.accent)
                    .padding(12)
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if settings.languageCode == "ar" {
            return hour < 17 ? "صباح الخير" : "مساء الخير"
        }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text(settings.languageCode == "ar" ? (settings.budgetMode == "Category" ? "المتبقي هذا الشهر" : "المتبقي اليوم") : snapshot.periodTitle.uppercased())
                    .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(theme.accentContrast.opacity(0.72))

                Spacer()

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accentContrast.opacity(0.74))
            }

            Text(snapshot.hasBudget
                 ? GhafFormat.money(snapshot.remaining, currency: settings.currency)
                 : (settings.languageCode == "ar" ? "أكمل ميزانيتك" : "Set your budget"))
                .font(GhafTypography.number(snapshot.hasBudget ? 42 : 29, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.accentContrast)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("\(Int(snapshot.progress * 100))% used")
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                        .foregroundStyle(theme.accentContrast.opacity(0.86))

                    Spacer()

                    Text(statusTitle)
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                        .foregroundStyle(theme.accentContrast)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.accentContrast.opacity(0.16))
                        Capsule()
                            .fill(theme.comfortable)
                            .frame(width: geometry.size.width * min(max(snapshot.progress, 0), 1))
                    }
                }
                .frame(height: 7)
            }

            Rectangle()
                .fill(theme.accentContrast.opacity(0.18))
                .frame(height: 1)

            HStack(spacing: 0) {
                budgetMetric(title: settings.languageCode == "ar" ? "الميزانية" : "BUDGET", amount: snapshot.limit)
                Spacer(minLength: 8)
                budgetMetric(title: settings.languageCode == "ar" ? "المصروف" : "SPENT", amount: snapshot.spent)
                Spacer(minLength: 8)
                budgetMetric(title: settings.languageCode == "ar" ? "المتبقي" : "LEFT", amount: snapshot.remaining, alignment: .trailing)
            }

            if !snapshot.hasBudget {
                Text(settings.budgetMode == "Category"
                     ? "Add category budgets in Settings."
                     : "Add your monthly income in Settings.")
                    .font(GhafTypography.body(12, languageCode: settings.languageCode))
                    .foregroundStyle(theme.accentContrast.opacity(0.78))
            }
        }
        .padding(22)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.accentContrast.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: theme.accent.opacity(0.13), radius: 18, x: 0, y: 8)
    }

    private func budgetMetric(
        title: String,
        amount: Decimal,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(title)
                .font(GhafTypography.body(9, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(theme.accentContrast.opacity(0.64))

            Text(GhafFormat.money(amount, currency: settings.currency))
                .font(GhafTypography.number(14, weight: .semibold))
                .foregroundStyle(theme.accentContrast)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var statusTitle: String {
        if settings.languageCode == "ar" {
            switch snapshot.status {
            case .comfortable: return "ضمن الحد"
            case .close: return "اقتربت من الحد"
            case .over: return "تجاوزت الحد"
            }
        }
        switch snapshot.status {
        case .comfortable: return "On track"
        case .close: return "Near limit"
        case .over: return "Over budget"
        }
    }

    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(theme.accent.opacity(0.10))
                        .frame(width: 52, height: 52)
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(theme.accent)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(settings.languageCode == "ar" ? "فعّل التتبع التلقائي" : "Automate your bank tracking")
                        .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.leading)

                    Text(settings.languageCode == "ar"
                         ? "غاف جاهز. افتح اختصارات لإكمال الربط."
                         : "Ghaf is ready. Open Shortcuts to connect your bank.")
                        .font(GhafTypography.body(13, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 2)
            }

            ShortcutsLink(action: {})
                .shortcutsLinkStyle(.automatic)
                .frame(maxWidth: .infinity)

            Text(settings.languageCode == "ar"
                 ? "الإجراء الجاهز من غاف سيظهر في تطبيق الاختصارات."
                 : "Ghaf's ready-made action appears on its Shortcuts page.")
                .font(GhafTypography.body(11, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)

            Button(settings.languageCode == "ar" ? "كيف يعمل الربط؟" : "How bank setup works") {
                showAutomationGuide = true
            }
            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.top, 1)
        }
        .padding(17)
        .ghafLiquidGlass(theme: theme, radius: 22)
    }

    private var manualEntryButton: some View {
        Button {
            showQuickAdd = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text(settings.languageCode == "ar" ? "أضف عملية يدوياً" : "Add transaction manually")
                    .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.languageCode == "ar" ? "حركة اليوم" : "Today")
                    .font(GhafTypography.display(25, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("\(todayTransactions.count) \(settings.languageCode == "ar" ? "عمليات" : "transactions")")
                    .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            if todayTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.languageCode == "ar" ? "لا توجد عمليات بعد" : "Nothing recorded today")
                        .font(GhafTypography.heading(17, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                    Text(settings.languageCode == "ar"
                         ? "ستظهر مصروفاتك هنا فور تسجيلها."
                         : "New spending will appear here as it is recorded.")
                        .font(GhafTypography.body(13, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .ghafCard(theme: theme, radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayTransactions.prefix(6)), id: \.id) { transaction in
                        GhafTransactionRow(
                            transaction: transaction,
                            theme: theme,
                            languageCode: settings.languageCode
                        )
                        if transaction.id != todayTransactions.prefix(6).last?.id {
                            Divider()
                                .overlay(theme.outline)
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .ghafCard(theme: theme, radius: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(LocalizedStringKey(transaction.category))
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
                    Text("REVIEW")
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
        return NSLocalizedString(transaction.category, comment: "")
    }

    private var amountText: String {
        let prefix = transaction.direction == "credit" ? "+" : "−"
        return prefix + GhafFormat.money(transaction.amount, currency: transaction.currency)
    }
}

// MARK: - Manual Transaction Entry

struct GhafQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    let settings: GhafSettings

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
                    Text("New transaction")
                        .font(GhafTypography.display(30, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("AMOUNT")
                            .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(theme.secondaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(settings.currency)
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

                    fieldLabel("Merchant")
                    styledField("Merchant or store", text: $merchant)

                    fieldLabel("Type")
                    Picker("Type", selection: $direction) {
                        Text("Expense").tag("debit")
                        Text("Income").tag("credit")
                    }
                    .pickerStyle(.segmented)

                    fieldLabel("Category")
                    Picker("Category", selection: $category) {
                        ForEach(settings.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accent)

                    fieldLabel("Date")
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .tint(theme.accent)

                    fieldLabel("Note")
                    styledField("Optional note", text: $note)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(GhafTypography.body(13, languageCode: settings.languageCode))
                            .foregroundStyle(theme.over)
                    }

                    Button("Save transaction", action: save)
                        .ghafProminentButton(theme: theme)
                }
                .padding(22)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(theme.accent)
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
            errorMessage = "Enter a valid amount."
            return
        }

        let parsed = ParsedTransaction(
            amount: value,
            currency: settings.currency,
            merchant: merchant.isEmpty ? nil : merchant,
            date: date,
            direction: TransactionDirection(rawValue: direction) ?? .debit,
            confidence: 1.0,
            bank: nil
        )

        let transaction = GhafTransaction(
            fingerprint: "manual-\(UUID().uuidString)",
            parsed: parsed,
            category: category,
            needsReview: false,
            isReversal: false
        )
        transaction.note = note
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not save transaction."
        }
    }
}
