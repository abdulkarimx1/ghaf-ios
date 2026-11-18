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

    @State private var selectedTransaction: GhafTransaction?
    @State private var confirmed = 0

    let settings: GhafSettings

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var activeAccounts: [GhafAccount] { accounts.filter { !$0.isArchived } }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: systemColorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header.ghafEntrance(0)
                    if reviewTransactions.isEmpty {
                        allClear.ghafEntrance(1)
                    } else {
                        ForEach(reviewTransactions, id: \.id) { transaction in
                            card(transaction)
                                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                }
                .padding(.horizontal, GhafMetrics.gutter)
                .padding(.top, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
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
                    .presentationDragIndicator(.visible)
            }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 8) {
            GhafStatusMark(tint: reviewTransactions.isEmpty ? theme.comfortable : theme.close) {
                Image(systemName: reviewTransactions.isEmpty ? "checkmark" : "tray.full.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(reviewTransactions.isEmpty ? theme.comfortable : theme.close)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(reviewTransactions.isEmpty ? (ar ? "كل شيء مؤكد" : "All confirmed")
                 : ar ? "\(reviewTransactions.count) للمراجعة" : "\(reviewTransactions.count) to review")
                .font(GhafTypography.display(30, languageCode: lang))
                .foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
            Text(reviewTransactions.isEmpty
                 ? (ar ? "لا توجد عمليات تنتظر قرارك." : "Nothing is waiting for you.")
                 : (ar ? "أكّد الصحيح وصحّح الباقي. كل تصحيح يتعلمه غاف للمرة القادمة."
                       : "Confirm what's right, fix what isn't. Ghaf learns every correction."))
                .font(GhafTypography.body(14, languageCode: lang))
                .foregroundStyle(theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var allClear: some View {
        Text(ar ? "العمليات التي لا يتأكد منها غاف، مثل حساب غير معروف أو فئة غير واضحة، تظهر هنا."
                : "Anything Ghaf isn't sure about, like an unknown account or an unclear category, shows up here.")
            .font(GhafTypography.body(14, languageCode: lang))
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
            .ghafCard(theme: theme)
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
                GhafBrandBadge(name: name, fallbackTint: theme.accent, size: 40)
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

            HStack(spacing: 8) {
                Menu {
                    ForEach(activeAccounts) { item in
                        Button(item.name) {
                            transaction.accountID = item.id
                            try? modelContext.save()
                        }
                    }
                } label: {
                    chip(ar ? "الحساب" : "Account", account?.name ?? (ar ? "اختر" : "Choose"), missing: account == nil)
                }
                Button { selectedTransaction = transaction } label: {
                    chip(ar ? "الفئة" : "Category", GhafLocalization.category(transaction.category, languageCode: lang),
                         missing: transaction.category == "Other")
                }
                .buttonStyle(.ghafPress)
            }

            HStack(spacing: 10) {
                Button { selectedTransaction = transaction } label: {
                    Text(ar ? "تعديل" : "Edit").frame(maxWidth: .infinity)
                }
                .ghafGlassButton(theme: theme, languageCode: lang)
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                        transaction.needsReview = false
                        try? modelContext.save()
                    }
                    confirmed += 1
                } label: {
                    Label(ar ? "تأكيد" : "Confirm", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .ghafProminentButton(theme: theme, languageCode: lang)
                .disabled(account == nil)
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

    private func chip(_ label: String, _ value: String, missing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText)
            HStack(spacing: 4) {
                Text(value).font(GhafTypography.body(14, languageCode: lang, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(missing ? theme.close : theme.primaryText)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(missing ? theme.close.opacity(0.5) : .clear, lineWidth: 1))
    }
}
