import SwiftUI
import SwiftData

/// Receipt for one transaction: what happened, from where to where, when, and where it came from.
/// Editing opens the existing editor on top; the receipt updates live from the model.
struct GhafTransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    let transaction: GhafTransaction
    let settings: GhafSettings
    let accounts: [GhafAccount]

    @State private var editing = false

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: systemColorScheme == .dark)
    }
    private var isCredit: Bool { transaction.direction == "credit" }
    private var account: GhafAccount? { accounts.first { $0.id == transaction.accountID } }
    private var merchantName: String {
        let name = transaction.merchant?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? GhafLocalization.category(transaction.category, languageCode: lang) : name
    }

    private var status: (title: String, symbol: String, tint: Color) {
        if transaction.needsReview { return (ar ? "تحتاج مراجعة" : "Needs review", "exclamationmark", theme.close) }
        if transaction.isReversal { return (ar ? "تم الاسترداد" : "Refund received", "arrow.uturn.backward", theme.credit) }
        if !transaction.isSpendingOrIncome { return (ar ? "تحويل" : "Transfer", "arrow.left.arrow.right", theme.accent) }
        return isCredit ? (ar ? "تم الاستلام" : "Money received", "arrow.down", theme.credit)
                        : (ar ? "تم الدفع" : "Payment made", "checkmark", theme.accent)
    }

    private var source: String {
        let f = transaction.fingerprint
        if f.hasPrefix("wallet-") { return "Apple Pay" }
        if f.hasPrefix("voice-") { return ar ? "غاف AI" : "Ghaf AI" }
        if f.hasPrefix("expend-") { return ar ? "مستورد من Expend" : "Imported from Expend" }
        if f.hasPrefix("manual-") { return ar ? "إدخال يدوي" : "Added by hand" }
        return ar ? "رسالة البنك" + (transaction.bank.map { " · \($0)" } ?? "") : "Bank message" + (transaction.bank.map { " · \($0)" } ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header.ghafEntrance(0)
                    receipt.ghafEntrance(1)
                    if transaction.needsReview { reviewBanner }
                    GhafMerchantDetailView(transaction: transaction, theme: theme, languageCode: lang)
                    bankContact
                }
                .ghafScreenPadding()
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .ghafBackground(theme: theme)
            .safeAreaInset(edge: .bottom) {
                GhafDetailActionBar(theme: theme, languageCode: lang,
                                    secondarySymbol: "pencil", secondaryLabel: ar ? "تعديل" : "Edit",
                                    secondaryAction: { editing = true },
                                    primaryTitle: ar ? "تم" : "Done", primaryAction: { dismiss() })
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: receiptText) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(ar ? "مشاركة الإيصال" : "Share receipt")
                }
            }
            .sheet(isPresented: $editing) {
                GhafTransactionEditor(transaction: transaction, categories: settings.categories, themeName: settings.themeName,
                                      appearanceMode: settings.appearanceMode, languageCode: lang, accounts: accounts)
                    .presentationDragIndicator(.visible).ghafDirection(lang)
            }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 18) {
            // Who and when, like a receipt's first line.
            HStack(spacing: 12) {
                GhafBrandBadge(name: merchantName, fallbackTint: theme.accent, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(merchantName)
                        .font(GhafTypography.body(17, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(transaction.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(Locale(identifier: lang))))
                        .font(GhafTypography.body(13, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Text(isCredit ? "+" : "−").font(GhafTypography.number(40, weight: .heavy))
                    GhafMoneyLabel(amount: transaction.amount, currency: transaction.currency, languageCode: lang, size: 40)
                }
                .foregroundStyle(isCredit ? theme.credit : theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
                if let original = transaction.originalAmount, let code = transaction.originalCurrency {
                    GhafMoneyLabel(amount: original, currency: code, languageCode: lang, size: 15)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Label(status.title, systemImage: status.symbol + ".circle.fill")
                .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                .foregroundStyle(status.tint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(status.tint.opacity(0.12), in: Capsule())
        }
        .padding(18)
        .ghafCard(theme: theme)
        .padding(.top, 6)
    }

    private var receipt: some View {
        GhafDetailCard(theme: theme) {
            let accountName = account?.name ?? (ar ? "غير محدد" : "Not assigned")
            GhafDetailRow(label: isCredit ? (ar ? "إلى حساب" : "Into") : (ar ? "من حساب" : "From"), theme: theme, languageCode: lang) {
                HStack(spacing: 8) {
                    Text(accountName)
                    if let account, let card = GhafCardFace.mini(for: account, width: 34) { card }
                }
            }
            GhafDetailRow(label: ar ? "الفئة" : "Category",
                          text: GhafLocalization.category(transaction.category, languageCode: lang)
                            + (transaction.subcategory.map { " › \(GhafLocalization.category($0, languageCode: lang))" } ?? ""),
                          theme: theme, languageCode: lang)
            if transaction.originalAmount != nil, let code = transaction.originalCurrency {
                if let rate = transaction.exchangeRate {
                    GhafDetailRow(label: ar ? "سعر الصرف (تقديري)" : "Rate (estimate)",
                                  text: "1 \(code) = \(rate.formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: lang)))) \(transaction.currency)"
                                    + " · " + (transaction.exchangeRateDate ?? transaction.date).formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: lang)))
                                    + "\n" + (ar ? "سعر السوق من \(GhafExchangeRates.sourceName). قد يختلف سعر البنك ورسومه." : "Market rate from \(GhafExchangeRates.sourceName). Your bank's rate and fees may differ."),
                                  theme: theme, languageCode: lang)
                }
            }
            GhafDetailRow(label: ar ? "المصدر" : "Source", text: source, theme: theme, languageCode: lang)
            GhafDetailRow(label: ar ? "المرجع" : "Reference",
                          text: "#" + transaction.id.uuidString.prefix(8),
                          theme: theme, languageCode: lang, divider: transaction.note?.isEmpty == false)
            if let note = transaction.note, !note.isEmpty {
                GhafDetailRow(label: ar ? "ملاحظة" : "Note", text: note, theme: theme, languageCode: lang, divider: false)
            }
        }
    }

    /// Like Wallet's "Contact your bank": the issuer's support line for charges you don't recognise.
    @ViewBuilder
    private var bankContact: some View {
        if let contact = GhafBankSupportDirectory.contact(for: [transaction.bank, account?.institution, account?.name]),
           let url = URL(string: "tel:\(contact.localDialString)") {
            VStack(alignment: .leading, spacing: 8) {
                Link(destination: url) {
                    Label((ar ? "تواصل مع " : "Contact ") + (ar ? contact.nameArabic : contact.name), systemImage: "phone.fill")
                        .font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .ghafCard(theme: theme)
                }
                .buttonStyle(.ghafPress)
                Text(ar ? "لعملية لا تعرفها أو للاعتراض عليها، تواصل مع البنك مباشرة."
                        : "For a charge you don't recognise, or to dispute one, contact your bank.")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var reviewBanner: some View {
        Button { editing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 20))
                Text(ar ? "راجع الفئة والحساب، ثم احفظ." : "Check the category and account, then save.")
                    .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                Spacer()
                Image(systemName: ar ? "chevron.left" : "chevron.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(theme.close)
            .padding(14)
            .background(theme.close.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.ghafPress)
    }

    private var receiptText: String {
        let amount = (isCredit ? "+" : "-") + GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: lang)
        return [status.title, merchantName, amount,
                transaction.date.formatted(.dateTime.day().month().year().hour().minute()),
                account?.name, "#" + transaction.id.uuidString.prefix(8)]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
