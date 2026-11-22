import SwiftUI
import SwiftData
import GhafCore
import UIKit

struct GhafAccountsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GhafAccount.sortOrder) private var accounts: [GhafAccount]
    @Query private var transactions: [GhafTransaction]

    let settings: GhafSettings
    var zoomNamespace: Namespace.ID? = nil

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
        Group {
            if accounts.contains(where: \.isArchived) {
                ScrollView { walletContent(balances) }
            } else {
                walletContent(balances)
            }
        }
        .ghafBackground(theme: theme)
        // Canvas header: "Wallet" in the bar's row, the hide-balances eye trailing.
        .ghafPageTitle(lang == "ar" ? "المحفظة" : "Wallet", languageCode: lang, theme: theme)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { eyeButton } }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                GhafAccountEditorView(account: target.account, settings: settings)
            }.ghafDirection(settings.languageCode)
        }
        .modifier(WalletZoomDestination(namespace: zoomNamespace))
    }

    private func walletContent(_ balances: [UUID: Decimal]) -> some View {
        VStack(spacing: GhafMetrics.sectionSpacing) {
            if activeAccounts.isEmpty {
                emptyState
                Button { editorTarget = EditorTarget(account: nil) } label: {
                    Label(lang == "ar" ? "إضافة حساب أو محفظة" : "Add account or wallet", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .ghafProminentButton(theme: theme, languageCode: lang)
            } else {
                GhafWalletStack(accounts: activeAccounts, balances: balances, transactions: transactions, settings: settings,
                                theme: theme, onEdit: { editorTarget = EditorTarget(account: $0) },
                                onMove: moveAccount, onAdd: { editorTarget = EditorTarget(account: nil) })
                    .ghafEntrance(1)
            }
            if accounts.contains(where: \.isArchived) { archivedAccounts(balances) }
        }
        .ghafScreenPadding()
        .padding(.top, 4)
        .padding(.bottom, 30)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    @AppStorage(GhafFormat.hideBalancesKey) private var hideBalances = false

    private var eyeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.35)) { hideBalances.toggle() }
        } label: {
            Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 17, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(theme.primaryText)
                .frame(width: 44, height: 44)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hideBalances)
        .accessibilityLabel(lang == "ar" ? (hideBalances ? "إظهار الأرصدة" : "إخفاء الأرصدة")
                                         : (hideBalances ? "Show balances" : "Hide balances"))
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            GhafIconBadge(symbol: "wallet.pass.fill", tint: theme.accent, size: 60, theme: theme)
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

private struct WalletZoomDestination: ViewModifier {
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if #available(iOS 18, *), let namespace {
            content.navigationTransition(.zoom(sourceID: "home-accounts", in: namespace))
        } else {
            content
        }
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
    /// The plain face, chosen on purpose; otherwise a designed card or note is always shown.
    @State private var plainChosen = false
    @State private var addedCardName: String?
    private var isCash: Bool { accountType == .cash }
    private var defaultDesign: GhafCardDesign? {
        GhafCardDesign.defaultDesign(isCash: isCash, bank: GhafUAEBank.match([institution, name]))
    }
    private var shownDesign: GhafCardDesign? { plainChosen ? nil : (cardDesign ?? defaultDesign) }
    @State private var showCardRequest = false
    @FocusState private var nameFocused: Bool

    private let currencies = ["AED", "SAR", "KWD", "BHD", "OMR", "QAR"]

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GhafCardFace(account: account, name: name, institution: institution, lastFour: lastFourDigits,
                             design: shownDesign, width: 300)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .animation(.spring(duration: 0.4), value: shownDesign)
                    .ghafEntrance(0)
                designStrip.ghafEntrance(1)
                TextField(ar ? "اسم الحساب" : "Account name", text: $name,
                          prompt: Text(ar ? "اسم الحساب" : "Account name").foregroundStyle(theme.secondaryText))
                    .font(GhafTypography.heading(24, languageCode: lang)).foregroundStyle(theme.primaryText)
                    .tint(theme.accent).multilineTextAlignment(.center).focused($nameFocused).submitLabel(.done)
                    .frame(minHeight: 40).overlay(alignment: .bottom) {
                        if nameFocused { Rectangle().fill(theme.accent).frame(width: max(160, min(340, CGFloat(max(name.count, 10)) * 13 + 24)), height: 1.5) }
                    }
                GhafAmountField(value: $balanceText, currency: currency, label: ar ? "الرصيد الافتتاحي" : "Opening balance",
                                theme: theme, languageCode: lang, fontSize: 48, chromeless: true)
                    .padding(.top, 6)

                GhafFormCard(theme: theme) {
                    GhafFormMenuRow(icon: "creditcard", tint: theme.accent, title: ar ? "النوع" : "Type",
                                    value: accountTypeTitle(accountType), theme: theme, languageCode: lang) {
                        Picker(ar ? "النوع" : "Type", selection: $accountType) {
                            ForEach(GhafAccountType.allCases) { type in Text(accountTypeTitle(type)).tag(type) }
                        }
                    }
                    GhafFormDivider(theme: theme)
                    if !isCash {
                        GhafFormRow(icon: "building.columns", tint: theme.accent, title: ar ? "البنك" : "Bank", theme: theme, languageCode: lang) {
                            HStack(spacing: 6) {
                                TextField(ar ? "البنك أو الجهة" : "Bank or institution", text: $institution).multilineTextAlignment(.trailing)
                                Menu {
                                    ForEach(GhafUAEBank.all) { bank in Button(ar ? bank.ar : bank.en) { institution = bank.en } }
                                } label: { Image(systemName: "chevron.forward").foregroundStyle(theme.secondaryText) }
                                .accessibilityLabel(ar ? "اختر بنكاً" : "Choose a bank")
                            }
                        }
                        GhafFormDivider(theme: theme)
                    }
                    GhafFormMenuRow(icon: "dollarsign.circle", tint: theme.accent, title: ar ? "العملة" : "Currency",
                                    value: currency, theme: theme, languageCode: lang) {
                        Picker(ar ? "العملة" : "Currency", selection: $currency) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if accountType == .credit {
                        GhafFormDivider(theme: theme)
                        fieldRow(ar ? "الحد الائتماني" : "Credit limit") {
                            GhafAmountField(value: $creditLimitText, currency: currency, label: "", theme: theme, languageCode: lang, fontSize: 20, chromeless: true)
                        }
                    }
                    if !isCash {
                        GhafFormDivider(theme: theme)
                        fieldRow(ar ? "آخر ٤ أرقام للبطاقة" : "Card ending") {
                            GhafAmountField(value: $lastFourDigits, currency: nil, label: "", theme: theme, languageCode: lang, integerMode: true, maxDigits: 4, fontSize: 20, chromeless: true)
                                .onChange(of: lastFourDigits) { _, value in lastFourDigits = String(value.filter(\.isNumber).suffix(4)) }
                        }
                        Text(ar ? "لمطابقة تنبيهات البنك بهذا الحساب" : "Used to match bank alerts to this account")
                            .font(GhafTypography.body(11, languageCode: lang))
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 42)
                    }
                    GhafFormDivider(theme: theme)
                    GhafFormToggleRow(icon: "checkmark.circle", tint: theme.comfortable, title: ar ? "الحساب الرئيسي" : "Primary account", isOn: $isPrimary, theme: theme, languageCode: lang)
                    if let account {
                        GhafFormDivider(theme: theme)
                        GhafFormToggleRow(icon: "sum", tint: theme.comfortable, title: ar ? "ضمن الرصيد الإجمالي" : "Include in total balance", isOn: Bindable(account).includeInTotal, theme: theme, languageCode: lang)
                    }
                }
                Text(isCash ? (ar ? "محفظة كاش: تسجّل مصروفاتها بنفسك أو بصوتك." : "Cash wallet: log spending yourself or by voice.")
                              : (ar ? "حساب بنكي: يُحدَّث تلقائياً من رسائل البنك وApple Pay عبر الأتمتة." : "Bank account: updated through bank messages and Apple Pay automation."))
                    .font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, -8)

                if errorMessage {
                    Label(ar ? "تحقق من اسم الحساب والرصيد." : "Check the account name and balance.", systemImage: "exclamationmark.circle.fill")
                        .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.over)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if accountType.isBankAccount {
                    Text(ar ? GhafCardDesign.disclaimer.ar : GhafCardDesign.disclaimer.en)
                        .font(GhafTypography.body(11, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .ghafScreenPadding()
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .contentMargins(.bottom, 112, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .ghafBackground(theme: theme)
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: theme.background.opacity(0), location: 0),
                                   .init(color: theme.background, location: 0.2),
                                   .init(color: theme.background.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .offset(y: -44)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .tint(theme.accent)
        .safeAreaInset(edge: .bottom) {
            GhafDetailActionBar(theme: theme, languageCode: lang,
                                secondarySymbol: account == nil ? nil : "archivebox",
                                secondaryLabel: ar ? "أرشفة الحساب" : "Archive account",
                                secondaryAction: { showArchiveConfirmation = true },
                                primaryTitle: account == nil ? (ar ? "إضافة الحساب" : "Add account") : (ar ? "حفظ" : "Save"),
                                primaryAction: save)
                .overlay(alignment: .bottom) {
            if showArchiveConfirmation {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ar ? "أرشفة هذا الحساب؟" : "Archive this account?")
                        .font(GhafTypography.heading(18, languageCode: lang))
                        .foregroundStyle(theme.primaryText)
                    Text(ar ? "يختفي الحساب ويبقى سجل عملياته." : "The account is hidden and its transaction history is kept.")
                        .font(GhafTypography.body(14, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(ar ? "إلغاء" : "Cancel") { showArchiveConfirmation = false }
                            .ghafGlassButton(theme: theme, languageCode: lang)
                        Button(ar ? "أرشفة" : "Archive", role: .destructive) { archive() }
                            .ghafDestructiveButton(theme: theme, languageCode: lang)
                    }
                }
                .padding(18)
                .frame(maxWidth: 440)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.bottom, GhafMetrics.buttonHeight + 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
                }
        }
        .navigationTitle(account == nil ? (ar ? "إضافة حساب" : "Add account") : (ar ? "تعديل الحساب" : "Edit account"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ZStack {
                    Text(account == nil ? (ar ? "إضافة حساب" : "Add account") : (ar ? "تعديل الحساب" : "Edit account"))
                        .font(GhafTypography.body(17, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    HStack {
                        Button(ar ? "إلغاء" : "Cancel") { dismiss() }
                            .foregroundStyle(theme.accent)
                            .frame(width: 64, alignment: .leading)
                        Spacer()
                        Color.clear.frame(width: 64)
                    }
                    .padding(.horizontal, GhafMetrics.gutter)
                }
                .frame(width: UIScreen.main.bounds.width, height: 44)
            }
        }
        .ghafKeyboardDone()
        .overlay {
            if let addedCardName {
                GhafSuccessSplash(title: ar ? "تمت إضافة البطاقة" : "Card added", subtitle: addedCardName,
                                  theme: theme, languageCode: lang) { dismiss() }
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .onAppear(perform: load)
        // A card belongs to its bank: changing the bank drops a card from the old one.
        .onChange(of: GhafUAEBank.match([institution, name])?.id) { _, bank in
            if let design = cardDesign, design.bank != "cash", design.bank != bank { cardDesign = nil }
        }
        // Banknotes are for cash wallets only, and cards for the others.
        .onChange(of: accountType) { _, type in
            if type == .cash { institution = ""; lastFourDigits = "" }
            if let design = cardDesign, (design.bank == "cash") != (type == .cash) { cardDesign = nil }
        }
        .sheet(isPresented: $showCardRequest) {
            GhafCardRequestView(settings: settings,
                                bank: GhafUAEBank.match([institution, name]).map { ar ? $0.ar : $0.en } ?? institution).ghafDirection(settings.languageCode)
        }
    }

    /// Bank colours (automatic) or one of the real card images.
    private var designStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                // Cash wallets get banknotes; others their own bank's cards. The plain face comes last.
                ForEach(isCash ? GhafCardDesign.all.filter { $0.bank == "cash" }
                               : GhafCardDesign.cards(for: GhafUAEBank.match([institution, name]))) { design in
                    designOption(design, label: design.title)
                }
                designOption(nil, label: isCash ? (ar ? "بسيط" : "Plain") : (ar ? "ألوان البنك" : "Bank colours"))
                if accountType != .cash { cardRequestTile }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// Last tile: the user's card isn't in the catalog yet, so they can ask for it.
    private var cardRequestTile: some View {
        Button { showCardRequest = true } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.secondaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 92, height: 58)
                    .overlay { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.accent) }
                Text(ar ? "بطاقتك غير موجودة؟" : "Card not found?")
                    .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.ghafPress)
        .accessibilityHint(ar ? "اطلب إضافة تصميم بطاقتك" : "Ask for your card design to be added")
    }

    private func designOption(_ design: GhafCardDesign?, label: String) -> some View {
        let selected = shownDesign == design
        return Button { withAnimation(.snappy) { cardDesign = design; plainChosen = design == nil } } label: {
            VStack(spacing: 6) {
                GhafCardFace(account: account, name: name, institution: institution, lastFour: lastFourDigits, design: design, width: 92)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selected ? theme.accent : .clear, lineWidth: 2.5)
                    }
                Text(label)
                    .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                    .foregroundStyle(selected ? theme.primaryText : theme.secondaryText)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.ghafPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 6)
            GhafFormCard(theme: theme) { content() }
        }
    }

    private func fieldRow<Field: View>(_ label: String, divider: Bool = true, @ViewBuilder field: @escaping () -> Field) -> some View {
        VStack(spacing: 0) {
            GhafFormRow(icon: fieldIcon(label), tint: theme.accent, title: label, theme: theme, languageCode: lang) {
                field().font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.primaryText).multilineTextAlignment(.trailing)
            }
            if divider { GhafFormDivider(theme: theme) }
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, divider: Bool) -> some View {
        VStack(spacing: 0) {
            GhafFormToggleRow(icon: "checkmark.circle", tint: theme.comfortable, title: label, isOn: isOn,
                              theme: theme, languageCode: lang)
            if divider { GhafFormDivider(theme: theme) }
        }
    }

    private func fieldIcon(_ label: String) -> String {
        switch label {
        case "Name", "الاسم": "person.crop.circle"
        case "Bank", "البنك": "building.columns"
        case "Type", "النوع": "creditcard"
        case "Currency", "العملة": "dollarsign.circle"
        case "Available right now", "الرصيد المتاح الآن": "wallet.pass"
        case "Credit limit", "الحد الائتماني": "creditcard"
        case "Card ending", "آخر ٤ أرقام للبطاقة": "number"
        default: "square.grid.2x2"
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
            name = ""
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
        lastFourDigits = account.cardLast4 ?? ""
        isPrimary = account.isPrimary
        cardDesign = account.cardDesign.flatMap(GhafCardDesign.init(rawValue:))
        plainChosen = account.cardDesign == GhafCardDesign.plainID
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let balance = Decimal(string: balanceText),
              balance >= 0,
              lastFourDigits.isEmpty || lastFourDigits.count == 4 else {
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
            target.institution = institution.isEmpty || isCash ? nil : institution
            target.accountType = accountType.rawValue
            if target.currency == currency {
                // A new balance is recorded as an Adjustment for the difference, so history keeps the
                // change and earlier activity stays as it was. Adjustments are never spending or income.
                let current = GhafAccountBalanceCalculator.balance(for: target, transactions: transactions)
                let difference = balance - current
                if difference != 0 {
                    let parsed = ParsedTransaction(amount: abs(difference), currency: currency,
                                                   merchant: ar ? "تعديل الرصيد" : "Balance adjustment", date: .now,
                                                   direction: difference > 0 ? .credit : .debit, confidence: 1, bank: nil)
                    modelContext.insert(GhafTransaction(fingerprint: "manual-adjust-\(UUID().uuidString)", parsed: parsed,
                                                        category: "Adjustment", needsReview: false, isReversal: false,
                                                        accountID: target.id))
                }
            } else {
                // Another currency: earlier activity no longer counts, so the entered amount starts afresh.
                target.currency = currency
                target.openingBalance = balance
                target.openingDate = .now
            }
            target.creditLimit = Decimal(string: creditLimitText)
            target.cardLast4 = lastFourDigits.isEmpty || isCash ? nil : lastFourDigits
            target.isArchived = false
            target.isPrimary = isPrimary
            target.cardDesign = plainChosen ? GhafCardDesign.plainID : shownDesign?.rawValue
        } else {
            target = GhafAccount(
                name: cleanName,
                institution: institution.isEmpty || isCash ? nil : institution,
                accountType: accountType,
                currency: currency,
                openingBalance: balance,
                openingDate: .now,
                creditLimit: Decimal(string: creditLimitText),
                lastFourDigits: lastFourDigits.isEmpty || isCash ? nil : lastFourDigits,
                isPrimary: isPrimary,
                sortOrder: accounts.count
            )
            target.cardDesign = plainChosen ? GhafCardDesign.plainID : shownDesign?.rawValue
            modelContext.insert(target)
        }

        if isPrimary {
            for other in accounts where other.id != target.id {
                other.isPrimary = false
            }
        }

        do {
            try modelContext.save()
            if account == nil {
                withAnimation(.easeOut(duration: 0.25)) { addedCardName = cleanName }
            } else {
                dismiss()
            }
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

/// Asks for a missing card design. The request goes out as an email the user sends themselves:
/// nothing is uploaded and no card number is asked for.
struct GhafCardRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var systemColorScheme
    let settings: GhafSettings
    @State var bank: String
    @State private var cardName = ""
    @State private var looks = ""
    @State private var link = ""
    @State private var copied = false

    init(settings: GhafSettings, bank: String) {
        self.settings = settings
        _bank = State(initialValue: bank)
    }

    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: systemColorScheme == .dark)
    }
    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var canSend: Bool { !bank.trimmingCharacters(in: .whitespaces).isEmpty && !cardName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(ar ? "أخبرنا عن بطاقتك وسنضيف تصميمها في تحديث قادم."
                            : "Tell us about your card and we'll add its design in an update.")
                        .font(GhafTypography.body(15, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                    GhafFormCard(theme: theme) {
                        field(ar ? "البنك" : "Bank", text: $bank, prompt: ar ? "مثال: مصرف عجمان" : "e.g. Ajman Bank")
                        GhafFormDivider(theme: theme)
                        field(ar ? "اسم البطاقة" : "Card name", text: $cardName, prompt: ar ? "مثال: بلاتينيوم" : "e.g. Platinum")
                        GhafFormDivider(theme: theme)
                        field(ar ? "رابط (اختياري)" : "Link (optional)", text: $link,
                              prompt: ar ? "صفحة البطاقة على موقع البنك" : "Card page on the bank's site",
                              divider: false, keyboard: .URL, autocorrection: false, capitalization: .never)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ar ? "كيف تبدو" : "How it looks")
                            .font(GhafTypography.body(14, languageCode: lang, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 6)
                        GhafTextField(text: $looks, placeholder: ar ? "الألوان والشعار والنقوش…" : "Colours, logo, pattern…", theme: theme, languageCode: lang, multiline: true)
                    }
                    Label(ar ? "لا تكتب رقم بطاقتك أو أي بيانات خاصة." : "Don't include your card number or other private details.",
                          systemImage: "lock.fill")
                        .font(GhafTypography.body(12, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                    if copied {
                        Text(ar ? "لا يوجد تطبيق بريد. نسخنا التفاصيل لترسلها بالطريقة التي تفضلها."
                                : "No mail app is set up. The details were copied so you can send them another way.")
                            .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .ghafScreenPadding()
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .ghafBackground(theme: theme)
            .tint(theme.accent)
            .safeAreaInset(edge: .bottom) {
                GhafDetailActionBar(theme: theme, languageCode: lang,
                                    primaryTitle: ar ? "أرسل الطلب" : "Send request", primaryAction: send)
                    .disabled(!canSend).opacity(canSend ? 1 : 0.5)
            }
            .navigationTitle(ar ? "طلب بطاقة" : "Request a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(ar ? "إلغاء" : "Cancel") { dismiss() } }
            }
            .ghafKeyboardDone()
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, divider: Bool = true,
                       keyboard: UIKeyboardType = .default, autocorrection: Bool = true,
                       capitalization: TextInputAutocapitalization = .sentences) -> some View {
        GhafTextField(text: text, placeholder: prompt, theme: theme, languageCode: lang,
                      label: label, chromeless: true, clearable: false, keyboard: keyboard,
                      autocorrection: autocorrection, capitalization: capitalization)
        .frame(minHeight: 72)
        .overlay(alignment: .bottom) { if divider { Divider().overlay(theme.outline) } }
    }

    private var details: String {
        ["Bank: \(bank)", "Card: \(cardName)", looks.isEmpty ? nil : "Looks: \(looks)", link.isEmpty ? nil : "Link: \(link)"]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private func send() {
        var mail = URLComponents()
        mail.scheme = "mailto"
        // shortcut: no recipient until Ghaf has a support address; the user fills it in Mail (same as Send feedback).
        mail.queryItems = [URLQueryItem(name: "subject", value: "Ghaf card request: \(bank) \(cardName)"),
                           URLQueryItem(name: "body", value: details)]
        guard let url = mail.url else { return }
        openURL(url) { accepted in
            if accepted { dismiss() } else { UIPasteboard.general.string = details; copied = true }
        }
    }
}
