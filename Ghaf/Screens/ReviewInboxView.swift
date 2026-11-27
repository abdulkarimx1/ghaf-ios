import SwiftUI
import SwiftData
import GhafCore

/// Transactions Ghaf was not sure about. Each card says why it is here and fixes the common case in
/// place (which account); the category opens the editor, so the correction is learned.
struct GhafReviewInboxView: View {
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<GhafTransaction> { $0.needsReview }, sort: \GhafTransaction.date, order: .reverse)
    private var reviewTransactions: [GhafTransaction]

    @Query private var allTransactions: [GhafTransaction]

    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]

    @Query(filter: #Predicate<GhafSubscription> { $0.needsConfirmation }, sort: \GhafSubscription.nextPaymentDate)
    private var detectedSubscriptions: [GhafSubscription]

    @State private var selectedTransaction: GhafTransaction?
    @State private var showSubscriptions = false
    @State private var alerts = GhafEventNotifications.events
    @State private var confirmed = 0
    @State private var movedSimilar: [UUID: Int] = [:]
    @State private var saveFailed = false

    let settings: GhafSettings
    var initialTargetID: String? = nil

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var activeAccounts: [GhafAccount] { accounts.filter { !$0.isArchived } }
    private var activeAlerts: [GhafInboxEvent] {
        alerts.filter { $0.kind != .transactionReview && $0.kind != .detectedSubscription }
    }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: systemColorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            header.ghafEntrance(0)
                            if reviewTransactions.isEmpty && detectedSubscriptions.isEmpty && activeAlerts.isEmpty {
                                Spacer(minLength: 0)
                                allClear.ghafEntrance(1)
                                Spacer(minLength: 0)
                            } else {
                                if !reviewTransactions.isEmpty {
                                    inboxSection(ar ? "تحتاج إلى مراجعة" : "Needs review") {
                                        ForEach(reviewTransactions, id: \.id) { transaction in
                                            card(transaction).id(transaction.id.uuidString)
                                        }
                                    }
                                }
                                if !detectedSubscriptions.isEmpty {
                                    inboxSection(ar ? "اشتراكات مرصودة" : "Detected subscriptions") {
                                        ForEach(detectedSubscriptions, id: \.id) { subscription in
                                            detectedSubscriptionRow(subscription).id(subscription.id.uuidString)
                                        }
                                    }
                                }
                                if !activeAlerts.isEmpty {
                                    inboxSection(ar ? "التنبيهات" : "Alerts") {
                                        ForEach(activeAlerts) { event in
                                            alertRow(event).id(event.itemID ?? event.id)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minHeight: reviewTransactions.isEmpty && detectedSubscriptions.isEmpty && activeAlerts.isEmpty
                               ? max(0, viewport.size.height - 48) : nil)
                        .ghafScreenPadding()
                        .padding(.top, 18)
                        .padding(.bottom, 30)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                    .onAppear {
                        GhafEventNotifications.configure()
                        if let initialTargetID { DispatchQueue.main.async { proxy.scrollTo(initialTargetID, anchor: .top) } }
                    }
                    .refreshable {
                        _ = try? GhafTransferReconciliation.run(in: modelContext)
                        GhafEventNotifications.configure()
                        alerts = GhafEventNotifications.events
                    }
                    .onReceive(NotificationCenter.default.publisher(for: GhafEventNotifications.inboxUpdated)) { _ in
                        alerts = GhafEventNotifications.events
                    }
                }
            }
            .ghafBackground(theme: theme)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                        .accessibilityLabel(ar ? "إغلاق" : "Close")
                }
            }
            .sensoryFeedback(.success, trigger: confirmed)
            .sheet(item: $selectedTransaction) { transaction in
                GhafTransactionEditor(transaction: transaction, categories: settings.categories, themeName: settings.themeName,
                                      appearanceMode: settings.appearanceMode, languageCode: lang, accounts: activeAccounts)
                    .presentationDragIndicator(.visible).ghafDirection(lang)
            }
            .sheet(isPresented: $showSubscriptions) {
                GhafSubscriptionsView(settings: settings).presentationDragIndicator(.visible).ghafDirection(lang)
            }
            .alert(ar ? "تعذّر الحفظ. حاول مرة أخرى." : "Couldn't save. Try again.", isPresented: $saveFailed) {
                Button(ar ? "حسنًا" : "OK", role: .cancel) { }
            }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(ar ? "النشاط" : "Activity")
                .font(GhafTypography.display(30, languageCode: lang))
                .foregroundStyle(theme.primaryText)
            Text(ar ? "العمليات والاشتراكات والتنبيهات التي تحتاج انتباهك." : "Transactions, subscriptions and alerts that need your attention.")
                .font(GhafTypography.body(14, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var allClear: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(theme.comfortable)
            Text(ar ? "كل شيء محدّث" : "All caught up")
                .font(GhafTypography.heading(20, languageCode: lang)).foregroundStyle(theme.primaryText)
            Text(ar ? "ستظهر هنا العمليات والاشتراكات والتنبيهات التي تحتاج انتباهك." : "Transactions, detected subscriptions and alerts will appear here.")
                .font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 34).frame(maxWidth: .infinity, minHeight: 240)
    }

    private func inboxSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(GhafTypography.heading(19, languageCode: lang)).foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    private func detectedSubscriptionRow(_ subscription: GhafSubscription) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill").font(.system(size: 22)).foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                Text(ar ? "رُصد اشتراك متكرر. راجعه قبل تفعيله." : "A recurring charge was detected. Review it before tracking.")
                    .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 8)
            Button(ar ? "مراجعة" : "Review") { showSubscriptions = true }
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold)).foregroundStyle(theme.accent)
        }
        .padding(16).ghafCard(theme: theme)
    }

    private func alertRow(_ event: GhafInboxEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind == .budgetThreshold ? "chart.bar.fill" : event.kind == .subscriptionDue ? "calendar" : "bell.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent).frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                Text(event.message).font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                Text(event.date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: lang))))
                    .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(16).ghafCard(theme: theme)
    }

    /// Why Ghaf held this one back, in the order the user should fix things.
    private func reason(_ transaction: GhafTransaction) -> (text: String, icon: String) {
        let duplicate = allTransactions.contains {
            $0.id != transaction.id && $0.amount == transaction.amount
                && $0.currency == transaction.currency
                && abs($0.date.timeIntervalSince(transaction.date)) < 86_400
                && MerchantName.key($0.merchant ?? "") == MerchantName.key(transaction.merchant ?? "")
                && !MerchantName.key(transaction.merchant ?? "").isEmpty
        }
        if duplicate { return (ar ? "عملية مكررة محتملة" : "Possible duplicate", "doc.on.doc") }
        if transaction.accountID == nil { return (ar ? "الحساب غير واضح" : "Account unclear", "creditcard.fill") }
        if !allTransactions.contains(where: { !$0.needsReview && MerchantName.key($0.merchant ?? "") == MerchantName.key(transaction.merchant ?? "") }) {
            return (ar ? "متجر جديد" : "New merchant", "storefront")
        }
        return (ar ? "تفاصيل غير واضحة" : "Details unclear", "questionmark.circle.fill")
    }

    private func card(_ transaction: GhafTransaction) -> some View {
        let isCredit = transaction.direction == "credit"
        let name = GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant)
            ?? GhafLocalization.category(transaction.category, languageCode: lang)
        let why = reason(transaction)
        let account = activeAccounts.first { $0.id == transaction.accountID }
        return VStack(spacing: 16) {
            Button { selectedTransaction = transaction } label: {
            HStack(spacing: 12) {
                GhafCategoryIcon(category: transaction.category, tint: theme.accent, theme: theme)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText).lineLimit(1)
                    Text(transaction.date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: lang))))
                        .font(GhafTypography.body(12, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                    Label(why.text, systemImage: why.icon)
                        .font(GhafTypography.body(11, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.close)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(theme.close.opacity(0.1), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text(isCredit ? "+" : "−").font(GhafTypography.number(30, weight: .heavy))
                    GhafMoneyLabel(amount: transaction.amount, currency: transaction.currency, languageCode: lang, size: 30)
                }
                .foregroundStyle(isCredit ? theme.credit : theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
                if let original = transaction.originalAmount, let code = transaction.originalCurrency {
                    GhafMoneyLabel(amount: original, currency: code, languageCode: lang, size: 13)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            if transaction.category == "Transfers" && transaction.transferDecision == nil {
                Text(ar ? "إلى حسابك أم إلى شخص آخر؟" : "Was this to your account or someone else?")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                HStack(spacing: 10) {
                    Button(ar ? "بين حساباتي" : "Between my accounts") {
                        transaction.category = "Transfers"; transaction.subcategory = "Between my accounts"
                        transaction.transferDecision = "own"; transaction.needsReview = false
                        if saveChanges() { confirmed += 1 }
                    }.ghafGlassButton(theme: theme, languageCode: lang)
                    Button(ar ? "إلى شخص آخر" : "To someone else") {
                        transaction.category = "Transfers"; transaction.subcategory = nil
                        transaction.transferDecision = "external"; transaction.needsReview = false
                        if saveChanges() { confirmed += 1 }
                    }.ghafGlassButton(theme: theme, languageCode: lang)
                }
            }

            VStack(spacing: 0) {
                Menu {
                    ForEach(activeAccounts) { item in
                        Button(item.name) {
                            transaction.accountID = item.id
                            // R5: only move similar alerts / learn a bank-wide rule when this bank has one account here.
                            // With two Mashreq accounts, picking one must change this item only.
                            var moved = 0
                            let learnsBank = transaction.bank.map { Self.accountsForBank($0, in: activeAccounts) <= 1 } ?? false
                            if learnsBank, let bank = transaction.bank {
                                moved = (try? GhafAccountMappings.apply(bank: bank, accountRef: nil, accountID: item.id, context: modelContext)) ?? 0
                            }
                            // Learn the bank rule only once the ledger change is saved.
                            guard saveChanges() else { return }
                            if learnsBank, let bank = transaction.bank {
                                if moved > 0 { movedSimilar[transaction.id] = moved }
                                GhafAccountMappings.confirm(transactionID: transaction.id, bank: bank, sender: nil, accountRef: nil, accountID: item.id)
                            }
                        }
                    }
                } label: {
                    GhafDetailRow(label: ar ? "الحساب" : "Account", theme: theme, languageCode: lang) {
                        menuValue(account?.name ?? (ar ? "اختر" : "Choose"), missing: account == nil)
                    }
                }
                .buttonStyle(.plain)
                Divider().overlay(theme.outline)
                Menu {
                    ForEach(settings.categories, id: \.self) { category in
                        Button(GhafLocalization.category(category, languageCode: lang)) {
                            transaction.category = category
                            transaction.subcategory = nil
                            _ = saveChanges()
                        }
                    }
                } label: {
                    GhafDetailRow(label: ar ? "الفئة" : "Category", theme: theme, languageCode: lang) {
                        menuValue(GhafLocalization.category(transaction.category, languageCode: lang),
                                  missing: transaction.category == "Other")
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button { selectedTransaction = transaction } label: {
                    Text(ar ? "تعديل" : "Edit")
                }
                .ghafGlassButton(theme: theme, languageCode: lang)
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        transaction.needsReview = false
                        if saveChanges() { confirmed += 1 }
                    }
                } label: {
                    Label(ar ? "تأكيد" : "Confirm", systemImage: "checkmark")
                }
                .ghafProminentButton(theme: theme, languageCode: lang)
                .disabled(account == nil)
            }
            .frame(maxWidth: .infinity)
            if let moved = movedSimilar[transaction.id], moved > 0 {
                Text(ar ? "ونُقلت \(GhafLocalization.count(moved, singular: "عملية مشابهة", dual: "عمليتان مشابهتان", plural: "عمليات مشابهة", afterTen: "عملية مشابهة", languageCode: lang))" : "Also moved \(moved) similar transactions")
                    .font(GhafTypography.body(12, languageCode: lang, weight: .medium))
                    .foregroundStyle(theme.comfortable)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            if account == nil {
                Text(ar ? "اختر الحساب أولاً حتى يُحتسب في الرصيد الصحيح." : "Pick the account first so it counts toward the right balance.")
                    .font(GhafTypography.body(11, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(16)
        .ghafCard(theme: theme)
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do { try modelContext.save(); return true }
        catch {
            modelContext.rollback()
            saveFailed = true
            return false
        }
    }

    private func menuValue(_ value: String, missing: Bool) -> some View {
        HStack(spacing: 6) {
            Text(value).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(missing ? theme.close : theme.primaryText)
    }
}

extension GhafReviewInboxView {
    /// How many active accounts could belong to `bank` (by institution or name), for the R5 guard.
    static func accountsForBank(_ bank: String, in accounts: [GhafAccount]) -> Int {
        let key = bank.lowercased().filter(\.isLetter)
        guard !key.isEmpty else { return 0 }
        return accounts.filter { account in
            [account.institution, account.name].compactMap { $0?.lowercased().filter(\.isLetter) }
                .contains { !$0.isEmpty && ($0.contains(key) || key.contains($0)) }
        }.count
    }
}
