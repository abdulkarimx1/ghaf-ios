import SwiftUI
import SwiftData

/// Transactions Ghaf was not sure about. Each card says why it is here and fixes the common case in
/// place (which account); the category opens the editor, so the correction is learned.
struct GhafReviewInboxView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<GhafTransaction> { $0.needsReview }, sort: \GhafTransaction.date, order: .reverse)
    private var reviewTransactions: [GhafTransaction]

    @Query(sort: \GhafAccount.sortOrder)
    private var accounts: [GhafAccount]

    @Query(filter: #Predicate<GhafSubscription> { $0.needsConfirmation }, sort: \GhafSubscription.nextPaymentDate)
    private var detectedSubscriptions: [GhafSubscription]

    @State private var selectedTransaction: GhafTransaction?
    @State private var showSubscriptions = false
    @State private var alerts = GhafEventNotifications.events
    @State private var confirmed = 0

    let settings: GhafSettings
    var initialTargetID: String? = nil

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var activeAccounts: [GhafAccount] { accounts.filter { !$0.isArchived } }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: systemColorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header.ghafEntrance(0)
                        if reviewTransactions.isEmpty && detectedSubscriptions.isEmpty && alerts.isEmpty {
                            allClear.ghafEntrance(1)
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
                            if !alerts.isEmpty {
                                inboxSection(ar ? "التنبيهات" : "Alerts") {
                                    ForEach(alerts) { event in
                                        alertRow(event).id(event.itemID ?? event.id)
                                    }
                                }
                            }
                        }
                    }
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
                .onReceive(NotificationCenter.default.publisher(for: GhafEventNotifications.inboxUpdated)) { _ in
                    alerts = GhafEventNotifications.events
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
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(ar ? "الإشعارات" : "Notifications")
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
            Text(ar ? "لا شيء ينتظر مراجعتك" : "You're all caught up")
                .font(GhafTypography.heading(20, languageCode: lang)).foregroundStyle(theme.primaryText)
            Text(ar ? "ستظهر هنا العمليات والاشتراكات والتنبيهات التي تحتاج انتباهك." : "Transactions, detected subscriptions and alerts will appear here.")
                .font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity).frame(minHeight: 300)
        .ghafCard(theme: theme)
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
        if transaction.accountID == nil { return (ar ? "من أي حساب؟" : "Which account?", "creditcard.fill") }
        if transaction.originalCurrency == nil && transaction.currency != settings.currency {
            return (ar ? "عملة أجنبية بدون سعر صرف" : "Foreign currency, no rate yet", "dollarsign.arrow.circlepath")
        }
        if transaction.isReversal { return (ar ? "استرداد لم يُربط بعملية" : "Refund not matched to a purchase", "arrow.uturn.backward") }
        if transaction.category == "Other" { return (ar ? "الفئة غير واضحة" : "Category unclear", "questionmark.circle.fill") }
        return (ar ? "تأكد من التفاصيل" : "Check the details", "eye.fill")
    }

    private func card(_ transaction: GhafTransaction) -> some View {
        let isCredit = transaction.direction == "credit"
        let name = transaction.merchant?.isEmpty == false ? transaction.merchant!
            : GhafLocalization.category(transaction.category, languageCode: lang)
        let why = reason(transaction)
        let account = activeAccounts.first { $0.id == transaction.accountID }
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                GhafCategoryIcon(category: transaction.category, tint: theme.accent, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText).lineLimit(1)
                    Text(transaction.date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: lang))))
                        .font(GhafTypography.body(12, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
                Label(why.text, systemImage: why.icon)
                    .font(GhafTypography.body(11, languageCode: lang, weight: .bold))
                    .foregroundStyle(theme.close)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(theme.close.opacity(0.1), in: Capsule())
                    .lineLimit(1)
            }

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

            VStack(spacing: 0) {
                Menu {
                    ForEach(activeAccounts) { item in
                        Button(item.name) {
                            transaction.accountID = item.id
                            try? modelContext.save()
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
                            try? modelContext.save()
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
                        .font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 24).frame(minHeight: 48)
                }
                .buttonStyle(.ghafPress)
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                        transaction.needsReview = false
                        try? modelContext.save()
                    }
                    confirmed += 1
                } label: {
                    Label(ar ? "تأكيد" : "Confirm", systemImage: "checkmark")
                        .font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.accentContrast)
                        .padding(.horizontal, 24).frame(minHeight: 48)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.ghafPress)
                .disabled(account == nil)
            }
            .frame(maxWidth: .infinity)
            if account == nil {
                Text(ar ? "اختر الحساب أولاً حتى يُحتسب في الرصيد الصحيح." : "Pick the account first so it counts toward the right balance.")
                    .font(GhafTypography.body(11, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(16)
        .ghafCard(theme: theme)
    }

    private func menuValue(_ value: String, missing: Bool) -> some View {
        HStack(spacing: 6) {
            Text(value).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(missing ? theme.close : theme.primaryText)
    }
}
