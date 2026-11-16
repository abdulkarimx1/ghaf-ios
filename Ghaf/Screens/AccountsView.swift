import SwiftUI
import SwiftData

struct GhafAccountsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var transactions: [GhafTransaction]

    let settings: GhafSettings

    /// One value drives the sheet so it always opens on the tapped account.
    private struct EditorTarget: Identifiable { let id = UUID(); let account: GhafAccount? }
    @State private var editorTarget: EditorTarget?

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

    private var lang: String { settings.languageCode }

    var body: some View {
        // One pass over transactions for every account, not one per row.
        let balances = GhafAccountBalanceCalculator.balances(accounts: accounts, transactions: transactions)
        ScrollView {
            VStack(spacing: GhafMetrics.sectionSpacing) {
                GhafScreenTitle(title: lang == "ar" ? "حساباتك ومحافظك" : "Accounts & wallets",
                                subtitle: lang == "ar" ? "رصيد كل حساب بعملته" : "Each account in its own currency",
                                languageCode: lang, theme: theme)

                if activeAccounts.isEmpty {
                    emptyState
                } else {
                    totalBalancesCard(GhafAccountBalanceCalculator.balancesByCurrency(accounts: activeAccounts, balances: balances))
                    accountList(balances).ghafEntrance(1)
                }

                Button {
                    editorTarget = EditorTarget(account: nil)
                } label: {
                    Label(
                        settings.languageCode == "ar" ? "إضافة حساب أو محفظة" : "Add account or wallet",
                        systemImage: "plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .ghafProminentButton(theme: theme, languageCode: settings.languageCode)

                if accounts.contains(where: \.isArchived) {
                    archivedAccounts(balances)
                }
            }
            .padding(.horizontal, GhafMetrics.gutter)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .navigationTitle(settings.languageCode == "ar" ? "الحسابات" : "Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                GhafAccountEditorView(account: target.account, settings: settings)
            }
        }
    }

    private func totalBalancesCard(_ currencyBalances: [GhafCurrencyBalance]) -> some View {
        VStack(spacing: 10) {
            Text(lang == "ar" ? "الإجمالي حسب العملة" : "Total by currency")
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            ForEach(currencyBalances) { item in
                GhafMoneyLabel(amount: item.amount, currency: item.currency, languageCode: lang,
                               size: currencyBalances.count == 1 ? 38 : 26)
                    .foregroundStyle(theme.primaryText)
            }
            Text(lang == "ar" ? "لا يتم تحويل العملات أو جمعها معاً." : "Different currencies are never converted or combined.")
                .font(GhafTypography.body(12, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 22).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .ghafCard(theme: theme, radius: 28)
    }

    private func accountList(_ balances: [UUID: Decimal]) -> some View {
        VStack(spacing: 10) {
            GhafSectionHeader(title: lang == "ar" ? "الحسابات النشطة" : "Active accounts", theme: theme, languageCode: lang)
            VStack(spacing: 0) {
                ForEach(activeAccounts, id: \.id) { account in
                    Button {
                        editorTarget = EditorTarget(account: account)
                    } label: {
                        accountRow(account, balance: balances[account.id] ?? account.openingBalance)
                    }
                    .buttonStyle(.ghafPress)
                    .contextMenu {
                        Button {
                            moveAccount(account, by: -1)
                        } label: {
                            Label(lang == "ar" ? "نقل إلى الأعلى" : "Move up", systemImage: "arrow.up")
                        }
                        .disabled(activeAccounts.first?.id == account.id)

                        Button {
                            moveAccount(account, by: 1)
                        } label: {
                            Label(lang == "ar" ? "نقل إلى الأسفل" : "Move down", systemImage: "arrow.down")
                        }
                        .disabled(activeAccounts.last?.id == account.id)
                    }
                    if account.id != activeAccounts.last?.id {
                        Divider().overlay(theme.outline).padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .ghafCard(theme: theme)
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

    private func accountRow(_ account: GhafAccount, balance: Decimal) -> some View {
        let detail = [account.institution ?? account.type.titleKey,
                      account.lastFourDigits.flatMap { $0.isEmpty ? nil : "•••• \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        return GhafListRow(icon: account.type.symbol, tint: theme.accent, title: account.name, subtitle: detail,
                           theme: theme, languageCode: lang, chevron: true,
                           cardAsset: account.cardDesign.flatMap(GhafCardDesign.init(rawValue:))?.asset) {
            GhafMoneyLabel(amount: balance, currency: account.currency, languageCode: lang, size: 16)
                .foregroundStyle(theme.primaryText)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            GhafIconBadge(symbol: "wallet.pass.fill", tint: theme.accent, size: 60)
            Text(settings.languageCode == "ar" ? "ابدأ بإضافة حسابك الأول" : "Add your first account")
                .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(settings.languageCode == "ar"
                 ? "يمكنك إضافة محفظتك النقدية وبطاقاتك وحساباتك البنكية."
                 : "Add your cash wallet, cards and bank accounts.")
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(22)
        .frame(maxWidth: .infinity)
        .ghafCard(theme: theme)
    }

    private func archivedAccounts(_ balances: [UUID: Decimal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang == "ar" ? "حسابات مؤرشفة" : "Archived")
                .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            ForEach(accounts.filter(\.isArchived), id: \.id) { account in
                HStack {
                    Text(account.name)
                        .font(GhafTypography.body(13, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    GhafMoneyLabel(amount: balances[account.id] ?? account.openingBalance,
                                   currency: account.currency, languageCode: settings.languageCode, size: 12)
                    .foregroundStyle(theme.secondaryText)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .ghafCard(theme: theme)
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
    @State private var cardDesign: GhafCardDesign?

    private let currencies = ["AED", "SAR", "KWD", "BHD", "OMR", "QAR"]

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
                if let account {
                    Toggle(settings.languageCode == "ar" ? "يُحسب في الرصيد الإجمالي" : "Include in total balance",
                           isOn: Bindable(account).includeInTotal)
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

            if accountType.isBankAccount {
                Section {
                    Picker(settings.languageCode == "ar" ? "تصميم البطاقة" : "Card design", selection: $cardDesign) {
                        Text(settings.languageCode == "ar" ? "بدون" : "None").tag(GhafCardDesign?.none)
                        ForEach(GhafCardDesign.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    if let cardDesign {
                        Image(cardDesign.asset).resizable().aspectRatio(1.6, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .frame(maxWidth: 320).frame(maxWidth: .infinity)
                            .accessibilityLabel(cardDesign.title)
                    }
                } header: {
                    Text(settings.languageCode == "ar" ? "البطاقة" : "CARD")
                } footer: {
                    Text(settings.languageCode == "ar" ? GhafCardDesign.disclaimer.ar : GhafCardDesign.disclaimer.en)
                }
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
        .ghafKeyboardDone()
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
        cardDesign = account.cardDesign.flatMap(GhafCardDesign.init(rawValue:))
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
            target.cardDesign = cardDesign?.rawValue
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
            target.cardDesign = cardDesign?.rawValue
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
