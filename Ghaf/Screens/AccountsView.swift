import SwiftUI
import SwiftData

struct GhafAccountsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var transactions: [GhafTransaction]

    let settings: GhafSettings

    @State private var selectedAccount: GhafAccount?
    @State private var showingEditor = false

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var activeAccounts: [GhafAccount] {
        accounts.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var currencyBalances: [GhafCurrencyBalance] {
        GhafAccountBalanceCalculator.balancesByCurrency(
            accounts: activeAccounts,
            transactions: transactions
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeading

                if activeAccounts.isEmpty {
                    emptyState
                } else {
                    totalBalancesCard
                    accountList
                }

                Button {
                    selectedAccount = nil
                    showingEditor = true
                } label: {
                    Label(
                        settings.languageCode == "ar" ? "إضافة حساب أو محفظة" : "Add account or wallet",
                        systemImage: "plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .ghafProminentButton(theme: theme, languageCode: settings.languageCode)

                if accounts.contains(where: \.isArchived) {
                    archivedAccounts
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(settings.languageCode == "ar" ? "الحسابات" : "Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                GhafAccountEditorView(account: selectedAccount, settings: settings)
            }
        }
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(settings.languageCode == "ar" ? "مصادر أموالك" : "MONEY SOURCES")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(theme.secondaryText)
            Text(settings.languageCode == "ar" ? "حساباتك ومحافظك" : "Accounts & wallets")
                .font(GhafTypography.display(30, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar"
                 ? "تابع رصيد كل حساب بعملته."
                 : "Track each account in its own currency.")
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var totalBalancesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.languageCode == "ar" ? "إجمالي الأرصدة حسب العملة" : "TOTAL BY CURRENCY")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(theme.secondaryText)

            ForEach(currencyBalances) { item in
                HStack {
                    Text(item.currency)
                        .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Text(GhafFormat.money(item.amount, currency: item.currency, languageCode: settings.languageCode))
                        .font(GhafTypography.number(20, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                }
            }

            Text(settings.languageCode == "ar"
                 ? "لا يتم تحويل العملات أو جمعها معاً."
                 : "Different currencies are never converted or combined.")
                .font(GhafTypography.body(11, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .ghafCard(theme: theme, radius: 20)
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.languageCode == "ar" ? "الحسابات النشطة" : "ACTIVE ACCOUNTS")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(theme.secondaryText)

            ForEach(activeAccounts, id: \.id) { account in
                Button {
                    selectedAccount = account
                    showingEditor = true
                } label: {
                    accountRow(account)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        moveAccount(account, by: -1)
                    } label: {
                        Label(
                            settings.languageCode == "ar" ? "نقل إلى الأعلى" : "Move up",
                            systemImage: "arrow.up"
                        )
                    }
                    .disabled(activeAccounts.first?.id == account.id)

                    Button {
                        moveAccount(account, by: 1)
                    } label: {
                        Label(
                            settings.languageCode == "ar" ? "نقل إلى الأسفل" : "Move down",
                            systemImage: "arrow.down"
                        )
                    }
                    .disabled(activeAccounts.last?.id == account.id)
                }
            }
        }
    }

    private func moveAccount(_ account: GhafAccount, by offset: Int) {
        guard let currentIndex = activeAccounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }
        let destinationIndex = currentIndex + offset
        guard activeAccounts.indices.contains(destinationIndex) else { return }
        let destination = activeAccounts[destinationIndex]
        let previousOrder = account.sortOrder
        account.sortOrder = destination.sortOrder
        destination.sortOrder = previousOrder
        try? modelContext.save()
    }

    private func accountRow(_ account: GhafAccount) -> some View {
        let balance = GhafAccountBalanceCalculator.balance(
            for: account,
            transactions: transactions
        )

        return HStack(spacing: 13) {
            Image(systemName: account.type.symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 46, height: 46)
                .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(account.institution ?? account.type.titleKey)
                    .font(GhafTypography.body(11, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                if let lastFour = account.lastFourDigits, !lastFour.isEmpty {
                    Text("•••• \(lastFour)")
                        .font(GhafTypography.number(10))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(GhafFormat.money(balance, currency: account.currency, languageCode: settings.languageCode))
                    .font(GhafTypography.number(15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(account.currency)
                    .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafLiquidGlass(theme: theme, radius: 19)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(theme.accent)
            Text(settings.languageCode == "ar" ? "ابدأ بإضافة حسابك الأول" : "Add your first account")
                .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar"
                 ? "يمكنك إضافة محفظتك النقدية وبطاقاتك وحساباتك البنكية."
                 : "Add your cash wallet, cards and bank accounts.")
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(20)
        .ghafCard(theme: theme, radius: 19)
    }

    private var archivedAccounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.languageCode == "ar" ? "حسابات مؤرشفة" : "ARCHIVED")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(theme.secondaryText)

            ForEach(accounts.filter(\.isArchived), id: \.id) { account in
                HStack {
                    Text(account.name)
                        .font(GhafTypography.body(13, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Text(GhafFormat.money(
                        GhafAccountBalanceCalculator.balance(for: account, transactions: transactions),
                        currency: account.currency,
                        languageCode: settings.languageCode
                    ))
                    .font(GhafTypography.number(12))
                    .foregroundStyle(theme.secondaryText)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .ghafCard(theme: theme, radius: 18)
    }
}

struct GhafAccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var accounts: [GhafAccount]
    @Query private var transactions: [GhafTransaction]

    let account: GhafAccount?
    let settings: GhafSettings

    @State private var name = ""
    @State private var institution = ""
    @State private var accountType: GhafAccountType = .cash
    @State private var currency = "AED"
    @State private var balanceText = "0"
    @State private var creditLimitText = ""
    @State private var lastFourDigits = ""
    @State private var isPrimary = false
    @State private var errorMessage = false
    @State private var showArchiveConfirmation = false

    private let currencies = ["AED", "USD", "SAR", "QAR", "KWD", "BHD", "OMR", "EUR", "GBP", "INR"]

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    var body: some View {
        Form {
            Section(settings.languageCode == "ar" ? "تفاصيل الحساب" : "ACCOUNT DETAILS") {
                TextField(settings.languageCode == "ar" ? "اسم الحساب" : "Account name", text: $name)
                TextField(settings.languageCode == "ar" ? "البنك أو الجهة" : "Bank or institution", text: $institution)

                Picker(settings.languageCode == "ar" ? "النوع" : "Type", selection: $accountType) {
                    ForEach(GhafAccountType.allCases) { type in
                        Text(accountTypeTitle(type)).tag(type)
                    }
                }

                Picker(settings.languageCode == "ar" ? "العملة" : "Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }

            Section(settings.languageCode == "ar" ? "الرصيد المتاح حالياً" : "CURRENT AVAILABLE BALANCE") {
                TextField("0.00", text: $balanceText)
                    .keyboardType(.decimalPad)

                if accountType == .credit {
                    TextField(
                        settings.languageCode == "ar" ? "الحد الائتماني (اختياري)" : "Credit limit (optional)",
                        text: $creditLimitText
                    )
                    .keyboardType(.decimalPad)
                }

                TextField(
                    settings.languageCode == "ar" ? "آخر ٤ أرقام فقط" : "Last 4 digits only",
                    text: $lastFourDigits
                )
                .keyboardType(.numberPad)
                .onChange(of: lastFourDigits) { _, value in
                    lastFourDigits = String(value.filter(\.isNumber).suffix(4))
                }

                Toggle(
                    settings.languageCode == "ar" ? "الحساب الرئيسي" : "Primary account",
                    isOn: $isPrimary
                )
            }

            if account != nil {
                Section {
                    Button(role: .destructive) {
                        showArchiveConfirmation = true
                    } label: {
                        Label(
                            settings.languageCode == "ar" ? "أرشفة الحساب" : "Archive account",
                            systemImage: "archivebox"
                        )
                    }
                } footer: {
                    Text(settings.languageCode == "ar"
                         ? "الأرشفة تخفي الحساب وتحافظ على سجل عملياته."
                         : "Archiving hides this account and preserves its transaction history.")
                }
            }

            if errorMessage {
                Section {
                    Text(settings.languageCode == "ar"
                         ? "تحقق من اسم الحساب والرصيد."
                         : "Check the account name and balance.")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(settings.languageCode == "ar" ? "حفظ الحساب" : "Save account", action: save)
                    .fontWeight(.semibold)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .tint(theme.accent)
        .navigationTitle(account == nil
                         ? (settings.languageCode == "ar" ? "إضافة حساب" : "Add account")
                         : (settings.languageCode == "ar" ? "تعديل الحساب" : "Edit account"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(settings.languageCode == "ar" ? "إلغاء" : "Cancel") { dismiss() }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog(
            settings.languageCode == "ar" ? "أرشفة هذا الحساب؟" : "Archive this account?",
            isPresented: $showArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(settings.languageCode == "ar" ? "أرشفة" : "Archive", role: .destructive) {
                archive()
            }
            Button(settings.languageCode == "ar" ? "إلغاء" : "Cancel", role: .cancel) {}
        }
    }

    private func accountTypeTitle(_ type: GhafAccountType) -> String {
        guard settings.languageCode == "ar" else { return type.titleKey }
        switch type {
        case .cash: return "محفظة نقدية"
        case .debit: return "بطاقة خصم"
        case .current: return "حساب جاري"
        case .savings: return "حساب توفير"
        case .credit: return "بطاقة ائتمان"
        case .prepaid: return "بطاقة مسبقة الدفع"
        }
    }

    private func load() {
        guard let account else {
            name = settings.languageCode == "ar" ? "محفظة نقدية" : "Cash wallet"
            accountType = .cash
            currency = settings.currency
            isPrimary = accounts.isEmpty
            return
        }

        name = account.name
        institution = account.institution ?? ""
        accountType = account.type
        currency = account.currency
        balanceText = GhafFormat.decimal(
            GhafAccountBalanceCalculator.balance(for: account, transactions: transactions)
        )
        creditLimitText = account.creditLimit.map(GhafFormat.decimal) ?? ""
        lastFourDigits = account.lastFourDigits ?? ""
        isPrimary = account.isPrimary
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let balance = Decimal(string: balanceText),
              balance >= 0 else {
            errorMessage = true
            return
        }

        if accountType == .credit,
           !creditLimitText.isEmpty,
           Decimal(string: creditLimitText) == nil {
            errorMessage = true
            return
        }

        let target: GhafAccount
        if let account {
            target = account
            target.name = cleanName
            target.institution = institution.isEmpty ? nil : institution
            target.accountType = accountType.rawValue
            target.currency = currency
            // The entered amount is a reconciliation as of now; earlier activity is already reflected.
            target.openingBalance = balance
            target.openingDate = .now
            target.creditLimit = Decimal(string: creditLimitText)
            target.lastFourDigits = lastFourDigits.isEmpty ? nil : lastFourDigits
            target.isArchived = false
            target.isPrimary = isPrimary
        } else {
            target = GhafAccount(
                name: cleanName,
                institution: institution.isEmpty ? nil : institution,
                accountType: accountType,
                currency: currency,
                openingBalance: balance,
                openingDate: .now,
                creditLimit: Decimal(string: creditLimitText),
                lastFourDigits: lastFourDigits.isEmpty ? nil : lastFourDigits,
                isPrimary: isPrimary,
                sortOrder: accounts.count
            )
            modelContext.insert(target)
        }

        if isPrimary {
            for other in accounts where other.id != target.id {
                other.isPrimary = false
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = true
        }
    }

    private func archive() {
        guard let account else { return }
        account.isArchived = true
        if settings.salaryAccountID == account.id {
            settings.salaryAccountID = nil
        }
        if account.isPrimary {
            accounts.first(where: { $0.id != account.id && !$0.isArchived })?.isPrimary = true
        }
        try? modelContext.save()
        dismiss()
    }
}
