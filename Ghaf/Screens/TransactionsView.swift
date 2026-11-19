import SwiftUI
import SwiftData

struct GhafTransactionsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]

    @State private var searchText = ""
    @State private var filter = "All"
    @State private var selectedTransaction: GhafTransaction?
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

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var sortOrderTitle: String {
        switch sortOrder {
        case "Oldest": ar ? "الأقدم" : "Oldest"
        case "Highest": ar ? "الأعلى" : "Highest"
        case "Lowest": ar ? "الأقل" : "Lowest"
        default: ar ? "الأحدث" : "Newest"
        }
    }

    /// Filtered once per render; search reads account names from a dictionary, not a scan per row.
    private func filtered() -> [GhafTransaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return transactions.filter { transaction in
            switch filter {
            case "Expenses": guard transaction.direction == "debit" else { return false }
            case "Income": guard transaction.direction == "credit" else { return false }
            case "Review": guard transaction.needsReview else { return false }
            default: break
            }
            guard !query.isEmpty else { return true }
            let searchValues = [
                transaction.merchant ?? "",
                transaction.category,
                GhafLocalization.category(transaction.category, languageCode: lang),
                transaction.bank ?? "",
                transaction.note ?? "",
                transaction.accountID.flatMap { accountNames[$0] } ?? ""
            ]
            return searchValues.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func ordered(_ list: [GhafTransaction]) -> [GhafTransaction] {
        switch sortOrder {
        case "Oldest": list.reversed()
        case "Highest": list.sorted { $0.currency == $1.currency ? $0.amount > $1.amount : $0.currency < $1.currency }
        case "Lowest": list.sorted { $0.currency == $1.currency ? $0.amount < $1.amount : $0.currency < $1.currency }
        default: list
        }
    }

    /// Day sections for date sorting; one section for amount sorting.
    private func sections(_ list: [GhafTransaction]) -> [(title: String, items: [GhafTransaction])] {
        guard sortOrder == "Newest" || sortOrder == "Oldest" else {
            return [(ar ? "حسب المبلغ" : "By amount", list)]
        }
        let calendar = Calendar.current
        var result: [(title: String, items: [GhafTransaction])] = []
        var currentDay: Date?
        for transaction in list {
            let day = calendar.startOfDay(for: transaction.date)
            if day != currentDay {
                currentDay = day
                result.append((dayTitle(day), []))
            }
            result[result.count - 1].items.append(transaction)
        }
        return result
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return ar ? "اليوم" : "Today" }
        if calendar.isDateInYesterday(day) { return ar ? "أمس" : "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.weekday(.wide).day().month(.wide)
            : .dateTime.day().month(.wide).year()
        return day.formatted(style.locale(Locale(identifier: lang)))
    }

    /// This month's totals in the preferred currency only.
    private func monthTotals(_ list: [GhafTransaction]) -> (spent: Decimal, income: Decimal) {
        let calendar = Calendar.current
        var spent = Decimal.zero, income = Decimal.zero
        for transaction in list where transaction.currency == settings.currency
            && calendar.isDate(transaction.date, equalTo: .now, toGranularity: .month) {
            if transaction.isExpense { spent += transaction.spendingAmount }
            income += transaction.incomeAmount
        }
        return (spent, income)
    }

    var body: some View {
        let list = filtered()
        let totals = monthTotals(list)
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        GhafScreenTitle(title: ar ? "العمليات" : "Transactions",
                                        subtitle: ar ? "كل حركة مالية في مكان واحد" : "Every movement, in one place",
                                        languageCode: lang, theme: theme)
                        monthSummary(totals)
                        searchField
                        filterBar(count: list.count)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: GhafMetrics.gutter, bottom: 4, trailing: GhafMetrics.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if list.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(sections(ordered(list)), id: \.title) { section in
                        Section {
                            ForEach(section.items) { transaction in
                                Button { selectedTransaction = transaction } label: {
                                    GhafTransactionRow(transaction: transaction, theme: theme, languageCode: lang)
                                }
                                .buttonStyle(.ghafPress)
                                .listRowInsets(EdgeInsets(top: 0, leading: GhafMetrics.gutter, bottom: 4, trailing: GhafMetrics.gutter))
                                .listRowBackground(Color.clear)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.surface))
                                .listRowSeparatorTint(theme.outline)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        transactionToDelete = transaction
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label(ar ? "حذف" : "Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(section.title)
                                .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                                .foregroundStyle(theme.secondaryText)
                                .textCase(nil)
                                .listRowInsets(EdgeInsets(top: 0, leading: GhafMetrics.gutter, bottom: 0, trailing: GhafMetrics.gutter))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(14)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .ghafBackground(theme: theme)
            .ghafKeyboardDone()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedTransaction) { transaction in
                GhafTransactionDetailView(transaction: transaction, settings: settings, accounts: accounts.filter { !$0.isArchived })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible).ghafDirection(settings.languageCode)
            }
            .confirmationDialog(
                ar ? "حذف هذه العملية؟" : "Delete this transaction?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(ar ? "حذف العملية" : "Delete transaction", role: .destructive) {
                    deletePendingTransaction()
                }
                Button(ar ? "إلغاء" : "Cancel", role: .cancel) {
                    transactionToDelete = nil
                }
            } message: {
                Text(ar ? "لا يمكن التراجع عن هذا الإجراء." : "This action cannot be undone.")
            }
        }
    }

    private func monthSummary(_ totals: (spent: Decimal, income: Decimal)) -> some View {
        HStack(spacing: 0) {
            summaryCell(ar ? "صرفت هذا الشهر" : "Spent this month", totals.spent, theme.debit, icon: "arrow.down.right")
            Rectangle().fill(theme.outline).frame(width: 1, height: 40)
            summaryCell(ar ? "الدخل هذا الشهر" : "Income this month", totals.income, theme.credit, icon: "arrow.up.right")
        }
        .padding(.vertical, 16)
        .ghafCard(theme: theme)
    }

    private func summaryCell(_ title: String, _ amount: Decimal, _ color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            GhafMoneyLabel(amount: amount, currency: settings.currency, languageCode: lang, size: 20)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        GhafTextField(text: $searchText, placeholder: ar ? "ابحث عن متجر أو فئة" : "Search merchant, category or bank",
                      theme: theme, languageCode: lang, icon: "magnifyingglass", autocorrection: false,
                      capitalization: .never, submitLabel: .search)
    }

    private func filterBar(count: Int) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton("All", label: ar ? "الكل" : "All")
                    filterButton("Expenses", label: ar ? "مصروفات" : "Expenses")
                    filterButton("Income", label: ar ? "دخل" : "Income")
                    filterButton("Review", label: ar ? "مراجعة" : "Review")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GhafMenuRow(title: ar ? "ترتيب" : "Sort", value: sortOrderTitle, theme: theme, languageCode: lang, compact: true) {
                Picker(ar ? "ترتيب" : "Sort", selection: $sortOrder) {
                    Text(ar ? "الأحدث" : "Newest").tag("Newest")
                    Text(ar ? "الأقدم" : "Oldest").tag("Oldest")
                    Text(ar ? "الأعلى" : "Highest").tag("Highest")
                    Text(ar ? "الأقل" : "Lowest").tag("Lowest")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(ar ? "ترتيب، \(count) عملية" : "Sort, \(count) transactions")
        }
    }

    private func filterButton(_ value: String, label: String) -> some View {
        let isSelected = filter == value
        return Button {
            withAnimation(.snappy(duration: 0.2)) { filter = value }
        } label: {
            Text(label)
                .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minHeight: GhafMetrics.compactButtonHeight)
                .foregroundStyle(isSelected ? theme.accentContrast : theme.primaryText)
                .background(isSelected ? theme.accent : theme.surface, in: Capsule())
        }
        .buttonStyle(.ghafPress)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            GhafIconBadge(symbol: "magnifyingglass", tint: theme.secondaryText, size: 56, theme: theme)
            Text(ar ? "لا توجد عمليات" : "No transactions found")
                .font(GhafTypography.heading(18, languageCode: lang))
                .foregroundStyle(theme.primaryText)
            Text(ar ? "جرّب تغيير البحث أو الفلتر." : "Try changing your search or filter.")
                .font(GhafTypography.body(14, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
    @State private var subcategory: String?
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
        _subcategory = State(initialValue: transaction.subcategory)
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
                    GhafAmountField(value: $amount, currency: transaction.currency,
                                    label: languageCode == "ar" ? "المبلغ" : "Amount",
                                    theme: theme, languageCode: languageCode)

                    editorLabel(languageCode == "ar" ? "المتجر" : "MERCHANT")
                    editorField("Merchant", text: $merchant)

                    editorLabel(languageCode == "ar" ? "النوع" : "TYPE")
                    GhafSegmented(options: [("debit", languageCode == "ar" ? "مصروف" : "Expense"), ("credit", languageCode == "ar" ? "دخل" : "Income")], selection: $direction, theme: theme, languageCode: languageCode)

                    editorLabel(languageCode == "ar" ? "الفئة" : "CATEGORY")
                    GhafCategoryPicker(category: $category, subcategory: $subcategory, languageCode: languageCode, tint: theme.accent)
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                        .padding(13)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 13), fallback: theme.surface)

                    if !accounts.isEmpty {
                        editorLabel(languageCode == "ar" ? "الحساب أو البطاقة" : "ACCOUNT OR CARD")
                        GhafMenuRow(title: languageCode == "ar" ? "الحساب" : "Account", value: accounts.first(where: { $0.id == accountID }).map { "\($0.name) · \($0.currency)" } ?? (languageCode == "ar" ? "غير محدد" : "Unassigned"), theme: theme, languageCode: languageCode) {
                            Picker(languageCode == "ar" ? "الحساب" : "Account", selection: $accountID) {
                                Text(languageCode == "ar" ? "غير محدد" : "Unassigned").tag(nil as UUID?)
                                ForEach(accounts, id: \.id) { account in
                                    Text("\(account.name) · \(account.currency)").tag(Optional(account.id))
                                }
                            }
                        }
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
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 13), fallback: theme.surface)

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

                            VStack(spacing: 10) {
                                Link(destination: URL(string: "tel:\(contact.localDialString)")!) {
                                    Label(
                                        languageCode == "ar" ? "محلي · \(contact.localPhone)" : "Local · \(contact.localPhone)",
                                        systemImage: "phone.fill"
                                    )
                                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                                }
                                .ghafGlassButton(theme: theme, languageCode: languageCode)
                                .frame(maxWidth: .infinity, minHeight: 56)

                                Link(destination: URL(string: "tel:\(contact.internationalDialString)")!) {
                                    Label(
                                        languageCode == "ar" ? "دولي" : "International",
                                        systemImage: "globe"
                                    )
                                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                                }
                                .ghafGlassButton(theme: theme, languageCode: languageCode)
                                .frame(maxWidth: .infinity, minHeight: 56)
                            }

                            Link(
                                languageCode == "ar" ? "الموقع الرسمي وطرق التواصل" : "Official contact details",
                                destination: contact.website
                            )
                            .font(GhafTypography.body(12, languageCode: languageCode))
                            .tint(theme.accent)
                        }
                        .padding(GhafMetrics.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 13), fallback: theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(theme.outline, lineWidth: 1))
                    }

                    editorLabel(languageCode == "ar" ? "التاريخ" : "DATE")
                    GhafDateRow(title: languageCode == "ar" ? "التاريخ" : "Date", selection: $date, components: [.date, .hourAndMinute], theme: theme, languageCode: languageCode)
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
            .ghafBackground(theme: theme)
            .ghafKeyboardDone()
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
            .font(GhafTypography.body(11, languageCode: languageCode, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(theme.secondaryText)
    }

    private func editorField(_ placeholder: String, text: Binding<String>) -> some View {
        GhafTextField(text: text, placeholder: placeholder, theme: theme, languageCode: languageCode)
    }

    private func save() {
        guard let value = Decimal(string: amount), value > 0 else {
            errorMessage = languageCode == "ar" ? "أدخل مبلغاً صحيحاً." : "Enter a valid amount."
            return
        }

        transaction.amount = value
        transaction.merchant = merchant.isEmpty ? nil : merchant
        transaction.category = category
        transaction.subcategory = subcategory
        transaction.direction = direction
        transaction.note = note
        transaction.date = date
        transaction.accountID = accountID
        transaction.needsReview = false

        if let merchantName = transaction.merchant, !merchantName.isEmpty {
            do {
                try MerchantCategorizer.learn(merchant: merchantName, category: category, subcategory: subcategory, context: modelContext)
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
