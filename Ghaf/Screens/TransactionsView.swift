import SwiftUI
import MapKit
import SwiftData

struct GhafTransactionsView: View {
    @Environment(GhafTabRouter.self) private var router
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var filter = "All"
    @State private var selectedTransaction: GhafTransaction?
    @State private var categoryTransaction: GhafTransaction?
    @State private var transactionDetailHeight: CGFloat = 0
    @State private var transactionDetailDetent: PresentationDetent = .large
    @State private var transactionToDelete: GhafTransaction?
    /// Owner 1.31: delete hides the row with Undo for 5 s; the ledger delete only happens when Undo isn't used.
    @State private var undoDelete: GhafTransaction?
    @Environment(\.scenePhase) private var deleteScenePhase
    @State private var cachedSections: [(title: String, items: [GhafTransaction])] = []
    @State private var cachedMonthTotals: (spent: Decimal, income: Decimal) = (.zero, .zero)
    @State private var cachedPreparationID: String?
    @State private var hasPreparedTransactions = false
#if DEBUG
    @State private var fixtureDetailOpened = false
#endif

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
    /// Filtered once per render; search reads account names from a dictionary, not a scan per row.
    private func filtered() -> [GhafTransaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if filter == "All", query.isEmpty { return transactions }
        let accountNames: [UUID: String] = query.isEmpty
            ? [:]
            : Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
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
                GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? "",
                transaction.category,
                GhafLocalization.category(transaction.category, languageCode: lang),
                transaction.bank ?? "",
                transaction.note ?? "",
                transaction.accountID.flatMap { accountNames[$0] } ?? ""
            ]
            return searchValues.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func sections(_ list: [GhafTransaction]) -> [(title: String, items: [GhafTransaction])] {
        let calendar = GhafCalendar.current
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

    private var preparationID: String {
        "\(transactions.count)-\(filter)-\(searchText)-\(lang)-\(accounts.count)-\(router.ledgerRevision)"
    }

    private func prepareVisibleTransactions() {
        guard cachedPreparationID != preparationID else { return }
#if DEBUG
        let prepared = GhafPerformanceProbe.measure("transactions-list") { prepareTransactionData() }
#else
        let prepared = prepareTransactionData()
#endif
        cachedMonthTotals = prepared.totals
        cachedSections = prepared.sections
        cachedPreparationID = preparationID
        hasPreparedTransactions = true
    }

    private func prepareTransactionData() -> (totals: (spent: Decimal, income: Decimal), sections: [(title: String, items: [GhafTransaction])]) {
        let list = filtered()
        return (monthTotals(list), sections(list))
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = GhafCalendar.current
        if calendar.isDate(day, inSameDayAs: GhafClock.now) { return ar ? "اليوم" : "Today" }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: GhafClock.now) ?? GhafClock.now
        if calendar.isDate(day, inSameDayAs: yesterday) { return ar ? "أمس" : "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: GhafClock.now, toGranularity: .year)
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
            && calendar.isDate(transaction.date, equalTo: GhafClock.now, toGranularity: .month) {
            if transaction.isExpense { spent += transaction.spendingAmount }
            income += transaction.incomeAmount
        }
        return (spent, income)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        GhafScreenTitle(title: ar ? "العمليات" : "Transactions",
                                        subtitle: ar ? "كل حركة مالية في مكان واحد" : "Every movement, in one place",
                                        languageCode: lang, theme: theme)
                        if hasPreparedTransactions {
                            monthSummary(cachedMonthTotals)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .accessibilityLabel(ar ? "جارٍ تحميل العمليات" : "Loading transactions")
                        }
                        searchField
                        filterBar
                    }
                    .listRowInsets(EdgeInsets(top: 32, leading: GhafMetrics.gutter, bottom: 4, trailing: GhafMetrics.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if !hasPreparedTransactions {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if cachedSections.isEmpty {
                    emptyState.ghafEntrance(1)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(cachedSections, id: \.title) { section in
                        Section {
                            Text(section.title)
                                .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                                .foregroundStyle(theme.secondaryText)
                                .listRowInsets(EdgeInsets(top: 8, leading: GhafMetrics.gutter, bottom: 2, trailing: GhafMetrics.gutter))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            ForEach(section.items.filter { $0.id != undoDelete?.id }) { transaction in
                                Button { selectedTransaction = transaction } label: {
                                    GhafTransactionRow(transaction: transaction, theme: theme, languageCode: lang)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                        .overlay(alignment: ar ? .topLeading : .topTrailing) {
                                            if transaction.isUnread {
                                                Circle().fill(theme.accent).frame(width: 7, height: 7)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                }
                                .buttonStyle(.ghafPress)
                                // Row 30: the gap is list spacing, not a row inset, so the swipe button matches the card.
                                .listRowInsets(EdgeInsets(top: 0, leading: GhafMetrics.gutter, bottom: 0, trailing: GhafMetrics.gutter))
                                .listRowBackground(Color.clear)
                                .background(RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous).fill(theme.surface))
                                .listRowSeparatorTint(theme.outline)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        startDelete(transaction)
                                    } label: {
                                        Label(ar ? "حذف" : "Delete", systemImage: "trash.fill").labelStyle(.iconOnly)
                                    }
                                    .tint(theme.over)
                                }
                                .contextMenu {
                                    Button { selectedTransaction = transaction } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil") }
                                    Button { categoryTransaction = transaction } label: { Label(ar ? "تغيير الفئة" : "Change category", systemImage: "square.grid.2x2") }
                                    Button(role: .destructive) { startDelete(transaction) } label: { Label(ar ? "حذف" : "Delete", systemImage: "trash") }
                                } preview: {
                                    GhafTransactionPeek(transaction: transaction, account: accounts.first { $0.id == transaction.accountID }, theme: theme, languageCode: lang)
                                        .padding(16).frame(width: 330).ghafCard(theme: theme)
                                }
                            }
                        }
                    }
                }
            }
            .ghafReportsTabBarMinimize()
            .listRowSpacing(4)
            .listStyle(.plain)
            .listSectionSpacing(14)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(theme.background.ignoresSafeArea())
            .ghafStatusBarFade(theme: theme)
            .ghafKeyboardDone()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: preparationID) { _, _ in prepareVisibleTransactions() }
            .onAppear { prepareVisibleTransactions() }
            .onAppear {
                let unread = transactions.filter(\.isUnread)
                guard !unread.isEmpty else { return }
                for transaction in unread { transaction.isUnread = false }
                try? modelContext.save()
            }
#if DEBUG
            .onAppear {
                if GhafScreenshotFixture.enabled, GhafScreenshotFixture.tab == "transactions",
                   GhafScreenshotFixture.selection == "transaction-detail", !fixtureDetailOpened,
                   let transaction = transactions.first(where: { $0.merchant == "Lunch" }) ?? transactions.first {
                    fixtureDetailOpened = true
                    selectedTransaction = transaction
                }
            }
#endif
            .sheet(item: $selectedTransaction) { transaction in
                GhafTransactionDetailView(transaction: transaction, settings: settings,
                                          accounts: accounts.filter { !$0.isArchived }) {
                    transactionDetailHeight = $0
                    transactionDetailDetent = $0 > UIScreen.main.bounds.height * 0.85 ? .large : .height($0)
                }
                    .presentationDetents(transactionDetailHeight == 0 ? [.large]
                                         : transactionDetailHeight > UIScreen.main.bounds.height * 0.85
                                            ? [.height(transactionDetailHeight), .large] : [.height(transactionDetailHeight)],
                                         selection: $transactionDetailDetent)
                    .presentationCornerRadius(32)
                    .presentationDragIndicator(.visible).ghafSheetFrame(theme: theme).ghafDirection(settings.languageCode)
            }
            .sheet(item: $categoryTransaction) { transaction in
                GhafQuickCategoryEditor(transaction: transaction, categories: settings.categories, theme: theme, languageCode: lang)
                    .ghafBottomCard(theme: theme, languageCode: lang)
            }
            .overlay(alignment: .bottom) {
                if let pending = undoDelete {
                    GhafUndoBar(message: ar ? "حُذفت \(pending.merchant ?? "العملية")" : "Deleted \(pending.merchant ?? "transaction")", theme: theme, languageCode: lang,
                                undo: { withAnimation(.easeOut(duration: 0.25)) { undoDelete = nil } },
                                finished: { withAnimation(.easeOut(duration: 0.25)) { commitUndoDelete() } })
                        .id(pending.id)
                        .padding(.horizontal, GhafMetrics.gutter)
                        .padding(.bottom, 12) // the tab bar is already inside this view's bottom safe area
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Leaving the app finishes the delete rather than keeping a hidden-but-alive row.
            .onChange(of: deleteScenePhase) { _, phase in if phase != .active { commitUndoDelete() } }
            .onDisappear { commitUndoDelete() }
        }
    }

    private func monthSummary(_ totals: (spent: Decimal, income: Decimal)) -> some View {
        HStack(spacing: 0) {
            summaryCell(ar ? "المصروف هذا الشهر" : "Spent this month", totals.spent, theme.debit,
                        identifier: "transactions.month.spent")
            Rectangle().fill(theme.outline).frame(width: 1, height: 40)
            summaryCell(ar ? "الدخل هذا الشهر" : "Income this month", totals.income, theme.credit,
                        identifier: "transactions.month.income")
        }
        .frame(minHeight: 116)
        .ghafCard(theme: theme)
    }

    private func summaryCell(_ title: String, _ amount: Decimal, _ color: Color, identifier: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GhafMoneyLabel(amount: amount, currency: settings.currency, languageCode: lang, size: 22)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier(identifier)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText).accessibilityHidden(true)
            TextField(ar ? "ابحث عن متجر أو فئة" : "Search merchant, category or bank", text: $searchText)
                .font(GhafTypography.userContent(searchText, size: 17, languageCode: lang))
                .foregroundStyle(theme.primaryText)
                .tint(theme.accent)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ar ? "مسح البحث" : "Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(theme.primaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(ar ? "بحث" : "Search")
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterButton("All", label: ar ? "الكل" : "All")
            filterButton("Expenses", label: ar ? "مصروفات" : "Expenses")
            filterButton("Income", label: ar ? "الدخل" : "Income")
            filterButton("Review", label: ar ? "مراجعة" : "Review")

        }
    }

    private func filterButton(_ value: String, label: String) -> some View {
        let isSelected = filter == value
        return Button {
            withAnimation(.snappy(duration: 0.2)) { filter = value }
        } label: {
            Text(label)
                .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 52)
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

    private func startDelete(_ transaction: GhafTransaction) {
        commitUndoDelete() // only one pending delete at a time
        withAnimation(.easeOut(duration: 0.25)) { undoDelete = transaction }
    }

    private func commitUndoDelete() {
        guard let pending = undoDelete else { return }
        undoDelete = nil
        transactionToDelete = pending
        deletePendingTransaction()
    }

    private func deletePendingTransaction() {
        guard let transaction = transactionToDelete else { return }
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            GhafSounds.shared.play(.deleted)
        } catch {
            modelContext.rollback()
        }
        transactionToDelete = nil
    }
}

private struct GhafQuickCategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let transaction: GhafTransaction
    let categories: [String]
    let theme: GhafTheme
    let languageCode: String
    @State private var category: String
    @State private var subcategory: String?
    @State private var errorMessage = ""

    init(transaction: GhafTransaction, categories: [String], theme: GhafTheme, languageCode: String) {
        self.transaction = transaction; self.categories = categories; self.theme = theme; self.languageCode = languageCode
        _category = State(initialValue: transaction.category); _subcategory = State(initialValue: transaction.subcategory)
    }
    var body: some View {
        VStack(spacing: 16) {
            GhafScreenTitle(title: languageCode == "ar" ? "تغيير الفئة" : "Change category", subtitle: GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant), languageCode: languageCode, theme: theme)
            GhafCategoryPicker(category: $category, subcategory: $subcategory, languageCode: languageCode, tint: theme.accent)
            if !errorMessage.isEmpty { Text(errorMessage).font(GhafTypography.body(13, languageCode: languageCode)).foregroundStyle(theme.over) }
            Button(languageCode == "ar" ? "حفظ" : "Save category", action: save)
                .buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .primary))
        }
        .padding(GhafMetrics.gutter).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.background)
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
    }
    private func save() {
        transaction.category = category; transaction.subcategory = subcategory
        if let merchant = transaction.merchant, !merchant.isEmpty {
            do { try MerchantCategorizer.learn(merchant: merchant, category: category, subcategory: subcategory, context: modelContext) }
            catch { errorMessage = languageCode == "ar" ? "تعذر حفظ الفئة." : "Could not save the category."; return }
        }
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); errorMessage = languageCode == "ar" ? "تعذر حفظ الفئة." : "Could not save the category." }
    }
}

private struct GhafTransactionPeek: View {
    let transaction: GhafTransaction
    let account: GhafAccount?
    let theme: GhafTheme
    let languageCode: String
    private var ar: Bool { languageCode == "ar" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GhafCategoryIcon(category: transaction.category, tint: theme.accent, theme: theme)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? GhafLocalization.category(transaction.category, languageCode: languageCode)).font(GhafTypography.heading(18, languageCode: languageCode)).foregroundStyle(theme.primaryText).lineLimit(1)
                    Text(GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: languageCode)).font(GhafTypography.number(18, weight: .bold)).foregroundStyle(transaction.isExpense ? theme.debit : theme.credit)
                }
            }
            peekRow(ar ? "الفئة" : "Category", GhafLocalization.category(transaction.category, languageCode: languageCode))
            peekRow(ar ? "الحساب" : "Account", account.map { "\($0.name) · \($0.currency)" } ?? (ar ? "غير محدد" : "Unassigned"))
            peekRow(ar ? "التاريخ" : "Date", transaction.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Locale(identifier: languageCode))))
            if let note = transaction.note, !note.isEmpty { peekRow(ar ? "ملاحظة" : "Note", note) }
            if let place = GhafPlaces.saved(merchant: transaction.merchant ?? "", transactionID: transaction.id) { peekRow(ar ? "المكان" : "Place", place.name ?? "") }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }
    private func peekRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(theme.secondaryText); Spacer(minLength: 12); Text(value).foregroundStyle(theme.primaryText).multilineTextAlignment(.trailing).lineLimit(2) }
            .font(GhafTypography.body(13, languageCode: languageCode))
    }
}

// MARK: - Transaction Editor

struct GhafTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()

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
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingDiscard = false
    @State private var showingMerchantRenameScope = false

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
        _merchant = State(initialValue: GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? "")
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
                    GhafTextField(text: $merchant, placeholder: languageCode == "ar" ? "المتجر" : "Merchant", theme: theme, languageCode: languageCode, autocorrection: false, capitalization: .words)
                        .accessibilityIdentifier("transaction-editor-merchant").lineLimit(1).submitLabel(.done)

                    editorLabel(languageCode == "ar" ? "النوع" : "TYPE")
                    GhafSegmented(options: [("debit", languageCode == "ar" ? "المصروف" : "Expense"), ("credit", languageCode == "ar" ? "الدخل" : "Income")], selection: $direction, theme: theme, languageCode: languageCode)

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
                                }
                                .ghafGlassButton(theme: theme, languageCode: languageCode)

                                Link(destination: URL(string: "tel:\(contact.internationalDialString)")!) {
                                    Label(
                                        languageCode == "ar" ? "دولي" : "International",
                                        systemImage: "globe"
                                    )
                                }
                                .ghafGlassButton(theme: theme, languageCode: languageCode)
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
                    HStack(spacing: 10) {
                        Button { showingDatePicker = true } label: {
                            Label(editDateLabel, systemImage: "calendar").font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, minHeight: 44)
                                .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
                        }.buttonStyle(.plain)
                        Button { showingTimePicker = true } label: {
                            Label(date.formatted(.dateTime.hour().minute().locale(Locale(identifier: languageCode))), systemImage: "clock")
                                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, minHeight: 44).background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
                        }.buttonStyle(.plain)
                    }

                    editorLabel(languageCode == "ar" ? "ملاحظة" : "NOTE")
                    editorField("Optional note", text: $note)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(GhafTypography.body(13, languageCode: languageCode))
                            .foregroundStyle(theme.over)
                    }

                    if !nameOK {
                        Text(languageCode == "ar" ? "أضف اسماً" : "Add a name")
                            .font(GhafTypography.body(13, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                    Button(languageCode == "ar" ? "حفظ التغييرات" : "Save changes", action: save)
                        .ghafProminentButton(theme: theme, languageCode: languageCode)
                        .disabled(!nameOK).opacity(nameOK ? 1 : 0.4)
                }
                .padding(22)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .ghafKeyboardDone()
            .interactiveDismissDisabled(isDirty)
            .overlay { if showingDiscard { GhafConfirmCard(title: languageCode == "ar" ? "هل تريد تجاهل هذه العملية؟" : "Discard this transaction?", message: languageCode == "ar" ? "ستفقد كل ما أدخلته." : "What you entered will be lost.", keepTitle: languageCode == "ar" ? "متابعة التعديل" : "Keep editing", discardTitle: languageCode == "ar" ? "تجاهل" : "Discard", theme: theme, languageCode: languageCode, keep: { showingDiscard = false }, discard: { showingDiscard = false; dismiss() }) } }
        .animation(.spring(duration: 0.38, bounce: 0.12), value: showingDiscard)
            .sheet(isPresented: $showingDatePicker) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        editQuickDate(languageCode == "ar" ? "اليوم" : "Today", value: GhafClock.now)
                        editQuickDate(languageCode == "ar" ? "أمس" : "Yesterday", value: Calendar.current.date(byAdding: .day, value: -1, to: GhafClock.now) ?? GhafClock.now)
                    }
                    DatePicker(languageCode == "ar" ? "التاريخ" : "Date", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().tint(theme.accent)
                }.padding(20).ghafBottomCard(theme: theme, languageCode: languageCode)
            }
            .sheet(isPresented: $showingTimePicker) {
                VStack(spacing: 8) {
                    DatePicker(languageCode == "ar" ? "الوقت" : "Time", selection: $date, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden().tint(theme.accent)
                    Button(languageCode == "ar" ? "تم" : "Done") { showingTimePicker = false }.buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .primary))
                }.padding(20).ghafBottomCard(theme: theme, languageCode: languageCode)
            }
            .navigationTitle(languageCode == "ar" ? "تعديل" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageCode == "ar" ? "إلغاء" : "Cancel") { if isDirty { showingDiscard = true } else { dismiss() } }
                }
            }
            .confirmationDialog(languageCode == "ar" ? "تغيير اسم المتجر" : "Rename this merchant", isPresented: $showingMerchantRenameScope) {
                Button(languageCode == "ar" ? "تغيير الاسم في كل العمليات المطابقة" : "Rename matching past transactions") { applySave(renameAll: true) }
                Button(languageCode == "ar" ? "هذه العملية فقط" : "Only this transaction") { applySave(renameAll: false) }
                Button(languageCode == "ar" ? "إلغاء" : "Cancel", role: .cancel) {}
            } message: {
                Text(languageCode == "ar" ? "هل تريد استخدام الاسم الجديد لكل العمليات التي وصل اسم متجرها من البنك بهذا الشكل؟" : "Use the new name for every transaction with this bank merchant name?")
            }
        }
    }

    private var isDirty: Bool {
        amount != GhafFormat.decimal(transaction.amount) || merchant != (GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? "") || category != transaction.category || note != (transaction.note ?? "") || date != transaction.date || direction != transaction.direction || accountID != transaction.accountID
    }
    private var editDateLabel: String {
        if Calendar.current.isDateInToday(date) { return languageCode == "ar" ? "اليوم" : "Today" }
        if Calendar.current.isDateInYesterday(date) { return languageCode == "ar" ? "أمس" : "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: languageCode)))
    }
    private func editQuickDate(_ title: String, value: Date) -> some View {
        Button(title) {
            date = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: date), minute: Calendar.current.component(.minute, from: date), second: 0, of: value) ?? value
            showingDatePicker = false
        }
        .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity, minHeight: 44).background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
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

    // A bank entry with no merchant (e.g. ATM) stays editable; only clearing an existing name is blocked.
    private var nameOK: Bool {
        transaction.direction == "transfer" || !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? "").isEmpty
    }

    private func save() {
        guard nameOK else { return }
        if transaction.bank != nil, let raw = transaction.rawMerchant ?? transaction.merchant,
           merchant != (GhafMerchantAliasStore.displayName(raw) ?? raw) {
            showingMerchantRenameScope = true
            return
        }
        applySave(renameAll: false)
    }

    private func applySave(renameAll: Bool) {
        guard let value = Decimal(string: amount), value > 0 else {
            errorMessage = languageCode == "ar" ? "أدخل مبلغاً صحيحاً." : "Enter a valid amount."
            return
        }

        var pendingAlias: (raw: String, display: String)?
        transaction.amount = value
        if renameAll, let raw = transaction.rawMerchant ?? transaction.merchant, !merchant.isEmpty {
            pendingAlias = (raw, merchant)
            transaction.rawMerchant = raw
            transaction.merchant = raw
        } else if merchant != (GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? "") {
            transaction.merchant = merchant.isEmpty ? nil : merchant
            transaction.rawMerchant = nil
        }
        transaction.category = category
        transaction.subcategory = subcategory
        transaction.direction = direction
        transaction.note = note
        transaction.date = date
        let accountChanged = transaction.accountID != accountID
        transaction.accountID = accountID
        transaction.needsReview = false
        // Only an account the user actually changed is learned (R6): saving a note must not turn a guess into a rule.
        if accountChanged, transaction.bank != nil, let accountID {
            GhafAccountMappings.confirm(transactionID: transaction.id, bank: transaction.bank, sender: nil, accountRef: nil, accountID: accountID)
        }

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
            if let pendingAlias { GhafMerchantAliasStore.rename(pendingAlias.raw, to: pendingAlias.display) }
            dismiss()
        } catch {
            errorMessage = languageCode == "ar" ? "تعذر حفظ التعديلات." : "Could not save changes."
        }
    }
}
