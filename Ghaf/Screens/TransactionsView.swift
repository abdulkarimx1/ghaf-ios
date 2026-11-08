import SwiftUI
import SwiftData

struct GhafTransactionsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @State private var searchText = ""
    @State private var filter = "All"
    @State private var selectedTransaction: GhafTransaction?
    @State private var showEditor = false
    @State private var sortOrder = "Newest"
    @State private var transactionToDelete: GhafTransaction?
    @State private var showDeleteConfirmation = false

    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var filteredTransactions: [GhafTransaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter { transaction in
            let matchesFilter: Bool
            switch filter {
            case "Expenses": matchesFilter = transaction.direction == "debit"
            case "Income": matchesFilter = transaction.direction == "credit"
            case "Review": matchesFilter = transaction.needsReview
            default: matchesFilter = true
            }
            let searchValues = [
                transaction.merchant ?? "",
                transaction.category,
                GhafLocalization.category(transaction.category, languageCode: settings.languageCode),
                transaction.bank ?? "",
                transaction.note ?? "",
                accounts.first(where: { $0.id == transaction.accountID })?.name ?? ""
            ]
            let matchesSearch = query.isEmpty || searchValues.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
            return matchesFilter && matchesSearch
        }
    }

    private var orderedTransactions: [GhafTransaction] {
        switch sortOrder {
        case "Oldest": filteredTransactions.sorted { $0.date < $1.date }
        case "Highest": filteredTransactions.sorted { lhs, rhs in
            lhs.currency == rhs.currency
                ? lhs.amount > rhs.amount
                : lhs.currency < rhs.currency
        }
        case "Lowest": filteredTransactions.sorted { lhs, rhs in
            lhs.currency == rhs.currency
                ? lhs.amount < rhs.amount
                : lhs.currency < rhs.currency
        }
        default: filteredTransactions.sorted { $0.date > $1.date }
        }
    }

    private var monthTransactions: [GhafTransaction] {
        filteredTransactions.filter {
            $0.currency == settings.currency &&
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }
    }

    private var monthExpenses: Decimal {
        monthTransactions.filter { $0.direction == "debit" }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var monthIncome: Decimal {
        monthTransactions.filter { $0.direction == "credit" }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    monthSummary
                    searchField
                    filterBar
                    transactionsContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditor) {
                transactionEditorSheet
            }
            .confirmationDialog(
                settings.languageCode == "ar" ? "حذف هذه العملية؟" : "Delete this transaction?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(settings.languageCode == "ar" ? "حذف العملية" : "Delete transaction", role: .destructive) {
                    deletePendingTransaction()
                }
                Button(settings.languageCode == "ar" ? "إلغاء" : "Cancel", role: .cancel) {
                    transactionToDelete = nil
                }
            } message: {
                Text(settings.languageCode == "ar" ? "لا يمكن التراجع عن هذا الإجراء." : "This action cannot be undone.")
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(settings.languageCode == "ar" ? "إدارة أموالك" : "YOUR MONEY")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(theme.secondaryText)
            Text(settings.languageCode == "ar" ? "العمليات" : "Transactions")
                .font(GhafTypography.display(32, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar" ? "كل حركة مالية في مكان واحد." : "Every recorded movement, all in one place.")
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var monthSummary: some View {
        HStack(spacing: 10) {
            summaryCell(
                title: settings.languageCode == "ar" ? "المصروفات (\(settings.currency))" : "SPENT IN \(settings.currency)",
                amount: monthExpenses,
                color: theme.debit
            )
            summaryCell(
                title: settings.languageCode == "ar" ? "الدخل (\(settings.currency))" : "INCOME IN \(settings.currency)",
                amount: monthIncome,
                color: theme.credit
            )
        }
    }

    private func summaryCell(title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(GhafTypography.body(9, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Text(GhafFormat.money(amount, currency: settings.currency, languageCode: settings.languageCode))
                .font(GhafTypography.number(19, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(theme.outline.opacity(0.65), lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            TextField(
                settings.languageCode == "ar" ? "ابحث عن متجر أو فئة" : "Search merchant, category or bank",
                text: $searchText
            )
            .font(GhafTypography.body(14, languageCode: settings.languageCode))
            .foregroundStyle(theme.primaryText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline, lineWidth: 1))
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            filterButton("All", label: settings.languageCode == "ar" ? "الكل" : "All")
            filterButton("Expenses", label: settings.languageCode == "ar" ? "مصروفات" : "Expenses")
            filterButton("Income", label: settings.languageCode == "ar" ? "دخل" : "Income")
            filterButton("Review", label: settings.languageCode == "ar" ? "مراجعة" : "Review")
        }
    }

    private func filterButton(_ value: String, label: String) -> some View {
        let isSelected = filter == value
        return Button {
            filter = value
        } label: {
            Text(label)
                .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 37)
                .foregroundStyle(isSelected ? theme.accentContrast : theme.secondaryText)
                .background(isSelected ? theme.accent : theme.surface, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? theme.accent : theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var transactionsContent: some View {
        if filteredTransactions.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Text(settings.languageCode == "ar" ? "لا توجد عمليات" : "No transactions found")
                    .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                Text(settings.languageCode == "ar" ? "جرّب تغيير البحث أو الفلتر." : "Try changing your search or filter.")
                    .font(GhafTypography.body(13, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .ghafCard(theme: theme, radius: 19)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(settings.languageCode == "ar" ? "سجل العمليات" : "Activity")
                        .font(GhafTypography.heading(19, languageCode: settings.languageCode))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Menu {
                        Button(settings.languageCode == "ar" ? "الأحدث أولاً" : "Newest first") { sortOrder = "Newest" }
                        Button(settings.languageCode == "ar" ? "الأقدم أولاً" : "Oldest first") { sortOrder = "Oldest" }
                        Button(settings.languageCode == "ar" ? "الأعلى مبلغاً" : "Highest amount") { sortOrder = "Highest" }
                        Button(settings.languageCode == "ar" ? "الأقل مبلغاً" : "Lowest amount") { sortOrder = "Lowest" }
                    } label: {
                        Label(settings.languageCode == "ar" ? "ترتيب" : "Sort", systemImage: "arrow.up.arrow.down")
                            .font(GhafTypography.body(11, languageCode: settings.languageCode, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    Text("\(filteredTransactions.count)")
                        .font(GhafTypography.number(12, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }

                VStack(spacing: 0) {
                    ForEach(orderedTransactions, id: \.id) { transaction in
                        Button {
                            selectedTransaction = transaction
                            showEditor = true
                        } label: {
                            GhafTransactionRow(
                                transaction: transaction,
                                theme: theme,
                                languageCode: settings.languageCode
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                transactionToDelete = transaction
                                showDeleteConfirmation = true
                            } label: {
                                Label(settings.languageCode == "ar" ? "حذف" : "Delete", systemImage: "trash")
                            }
                        }

                        Divider().overlay(theme.outline).padding(.leading, 58)
                    }
                }
                .padding(.horizontal, 14)
                .ghafCard(theme: theme, radius: 19)
            }
        }
    }

    private func deletePendingTransaction() {
        guard let transaction = transactionToDelete else { return }
        modelContext.delete(transaction)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
        transactionToDelete = nil
    }

    @ViewBuilder
    private var transactionEditorSheet: some View {
        if let transaction = selectedTransaction {
            GhafTransactionEditor(
                transaction: transaction,
                categories: settings.categories,
                themeName: settings.themeName,
                appearanceMode: settings.appearanceMode,
                languageCode: settings.languageCode,
                accounts: accounts.filter { !$0.isArchived }
            )
        }
    }
}

// MARK: - Transaction Editor

struct GhafTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    let transaction: GhafTransaction
    let categories: [String]
    let themeName: String
    let appearanceMode: String
    let languageCode: String

    @State private var amount: String
    @State private var merchant: String
    @State private var category: String
    @State private var direction: String
    @State private var note: String
    @State private var date: Date
    @State private var accountID: UUID?
    @State private var errorMessage = ""

    private let accounts: [GhafAccount]

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: themeName,
            appearanceMode: appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    init(
        transaction: GhafTransaction,
        categories: [String],
        themeName: String,
        appearanceMode: String,
        languageCode: String,
        accounts: [GhafAccount]
    ) {
        self.transaction = transaction
        self.themeName = themeName
        self.appearanceMode = appearanceMode
        self.languageCode = languageCode
        self.accounts = accounts

        var availableCategories = categories
        if !availableCategories.contains(transaction.category) {
            availableCategories.append(transaction.category)
        }
        self.categories = availableCategories
        _amount = State(initialValue: GhafFormat.decimal(transaction.amount))
        _merchant = State(initialValue: transaction.merchant ?? "")
        _category = State(initialValue: transaction.category)
        _direction = State(initialValue: transaction.direction)
        _note = State(initialValue: transaction.note ?? "")
        _date = State(initialValue: transaction.date)
        _accountID = State(initialValue: transaction.accountID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(languageCode == "ar" ? "تعديل العملية" : "Edit transaction")
                        .font(GhafTypography.display(29, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)

                    editorLabel(languageCode == "ar" ? "المبلغ" : "AMOUNT")
                    TextField("0.00", text: $amount)
                        .font(GhafTypography.number(30, weight: .bold))
                        .keyboardType(.decimalPad)
                        .padding(15)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 15))

                    editorLabel(languageCode == "ar" ? "المتجر" : "MERCHANT")
                    editorField("Merchant", text: $merchant)

                    editorLabel(languageCode == "ar" ? "النوع" : "TYPE")
                    Picker(languageCode == "ar" ? "النوع" : "Direction", selection: $direction) {
                        Text(languageCode == "ar" ? "مصروف" : "Expense").tag("debit")
                        Text(languageCode == "ar" ? "دخل" : "Income").tag("credit")
                    }
                    .pickerStyle(.segmented)

                    editorLabel(languageCode == "ar" ? "الفئة" : "CATEGORY")
                    Picker(languageCode == "ar" ? "الفئة" : "Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text(GhafLocalization.category($0, languageCode: languageCode)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accent)

                    if !accounts.isEmpty {
                        editorLabel(languageCode == "ar" ? "الحساب أو البطاقة" : "ACCOUNT OR CARD")
                        Picker(languageCode == "ar" ? "الحساب" : "Account", selection: $accountID) {
                            Text(languageCode == "ar" ? "غير محدد" : "Unassigned").tag(nil as UUID?)
                            ForEach(accounts, id: \.id) { account in
                                Text("\(account.name) · \(account.currency)").tag(Optional(account.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        editorLabel(languageCode == "ar" ? "تفاصيل المصدر" : "SOURCE DETAILS")
                        if let bank = transaction.bank, !bank.isEmpty {
                            Label(bank, systemImage: "building.columns")
                                .font(GhafTypography.body(13, languageCode: languageCode))
                                .foregroundStyle(theme.secondaryText)
                        }
                        if let account = accounts.first(where: { $0.id == accountID }) {
                            Label(account.name, systemImage: account.type.symbol)
                                .font(GhafTypography.body(13, languageCode: languageCode))
                                .foregroundStyle(theme.secondaryText)
                        }
                        Text(languageCode == "ar"
                            ? "بيانات موقع المتجر ورقمه غير متاحة في رسالة البنك."
                            : "The bank message does not include the merchant's location or phone number.")
                            .font(GhafTypography.body(10, languageCode: languageCode))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 13))

                    let selectedAccount = accounts.first(where: { $0.id == accountID })
                    if let contact = GhafBankSupportDirectory.contact(
                        for: [transaction.bank, selectedAccount?.institution, selectedAccount?.name]
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            editorLabel(languageCode == "ar" ? "دعم البنك" : "BANK SUPPORT")
                            Text(languageCode == "ar" ? contact.nameArabic : contact.name)
                                .font(GhafTypography.heading(16, languageCode: languageCode))
                                .foregroundStyle(theme.primaryText)
                            Text(languageCode == "ar" ? contact.countryNameArabic : contact.countryName)
                                .font(GhafTypography.body(11, languageCode: languageCode))
                                .foregroundStyle(theme.secondaryText)

                            HStack(spacing: 10) {
                                Link(destination: URL(string: "tel:\(contact.localDialString)")!) {
                                    Label(
                                        languageCode == "ar" ? "محلي · \(contact.localPhone)" : "Local · \(contact.localPhone)",
                                        systemImage: "phone.fill"
                                    )
                                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(theme.accent)

                                Link(destination: URL(string: "tel:\(contact.internationalDialString)")!) {
                                    Label(
                                        languageCode == "ar" ? "دولي" : "International",
                                        systemImage: "globe"
                                    )
                                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(theme.accent)
                            }

                            Link(
                                languageCode == "ar" ? "الموقع الرسمي وطرق التواصل" : "Official contact details",
                                destination: contact.website
                            )
                            .font(GhafTypography.body(12, languageCode: languageCode))
                            .tint(theme.accent)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(theme.outline, lineWidth: 1))
                    }

                    editorLabel(languageCode == "ar" ? "التاريخ" : "DATE")
                    DatePicker(languageCode == "ar" ? "التاريخ" : "Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .tint(theme.accent)

                    editorLabel(languageCode == "ar" ? "ملاحظة" : "NOTE")
                    editorField("Optional note", text: $note)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(GhafTypography.body(13, languageCode: languageCode))
                            .foregroundStyle(theme.over)
                    }

                    Button(languageCode == "ar" ? "حفظ التغييرات" : "Save changes", action: save)
                        .ghafProminentButton(theme: theme, languageCode: languageCode)
                }
                .padding(22)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(languageCode == "ar" ? "تعديل" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageCode == "ar" ? "إلغاء" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func editorLabel(_ value: String) -> some View {
        Text(value)
            .font(GhafTypography.body(10, languageCode: languageCode, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(theme.secondaryText)
    }

    private func editorField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(GhafTypography.body(15, languageCode: languageCode))
            .padding(13)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(theme.outline, lineWidth: 1))
    }

    private func save() {
        guard let value = Decimal(string: amount), value > 0 else {
            errorMessage = languageCode == "ar" ? "أدخل مبلغاً صحيحاً." : "Enter a valid amount."
            return
        }

        transaction.amount = value
        transaction.merchant = merchant.isEmpty ? nil : merchant
        transaction.category = category
        transaction.direction = direction
        transaction.note = note
        transaction.date = date
        transaction.accountID = accountID
        transaction.needsReview = false

        if let merchantName = transaction.merchant, !merchantName.isEmpty {
            do {
                try MerchantCategorizer.learn(merchant: merchantName, category: category, context: modelContext)
            } catch {
                errorMessage = languageCode == "ar" ? "تعذر حفظ قاعدة المتجر." : "Could not save merchant rule."
                return
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = languageCode == "ar" ? "تعذر حفظ التعديلات." : "Could not save changes."
        }
    }
}
