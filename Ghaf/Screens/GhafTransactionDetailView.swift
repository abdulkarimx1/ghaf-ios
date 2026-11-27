import SwiftUI
import SwiftData
import os

private let transactionDetailLayoutLog = OSLog(subsystem: "com.ghaf.app", category: "TransactionDetailLayout")

private struct GhafTransactionDetailHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Receipt for one transaction: what happened, from where to where, when, and where it came from.
/// Editing opens the existing editor on top; the receipt updates live from the model.
struct GhafTransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("ghaf.merchant.aliases") private var merchantAliases = Data()

    let transaction: GhafTransaction
    let settings: GhafSettings
    let accounts: [GhafAccount]
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var editing = false
    @State private var lastMeasuredHeight: CGFloat = 0

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: systemColorScheme == .dark)
    }
    private var isCredit: Bool { transaction.direction == "credit" }
    private var account: GhafAccount? { accounts.first { $0.id == transaction.accountID } }
    private var merchantName: String {
        let name = GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? GhafLocalization.category(transaction.category, languageCode: lang) : name
    }
    private var transactionDateLabel: String {
        let calendar = Calendar.current
        let time = transaction.date.formatted(.dateTime.hour().minute().locale(GhafLocale.locale(identifier: lang)))
        if calendar.isDateInToday(transaction.date) { return (ar ? "اليوم" : "Today") + (ar ? "، " : ", ") + time }
        if calendar.isDateInYesterday(transaction.date) { return (ar ? "أمس" : "Yesterday") + (ar ? "، " : ", ") + time }
        let day = transaction.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(GhafLocale.locale(identifier: lang)))
        return day + " · " + time
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
        ScrollView {
            VStack(spacing: 18) {
                header.ghafEntrance(0)
                receipt.ghafEntrance(1)
                if transaction.needsReview { reviewBanner }
                GhafMerchantDetailView(transaction: transaction, theme: theme, languageCode: lang,
                                       mapsAppPreference: settings.mapsAppPreference)
                bankContact
                HStack(spacing: 12) {
                    Button { editing = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 56, height: 56)
                            .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Circle())
                    }
                    .buttonStyle(.ghafPress)
                    .accessibilityLabel(ar ? "تعديل" : "Edit")
                    GhafPrimaryButton(title: ar ? "تم" : "Done", theme: theme, languageCode: lang) { dismiss() }
                }
            }
            .ghafScreenPadding()
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: GhafTransactionDetailHeightKey.self, value: proxy.size.height + 36)
                }
            }
            .onPreferenceChange(GhafTransactionDetailHeightKey.self) { height in
                guard height > 0, abs(lastMeasuredHeight - height) > 1 else { return }
                lastMeasuredHeight = height
                os_signpost(.event, log: transactionDetailLayoutLog, name: "MeasuredContentHeight", "%{public}.1f pt", height)
                onContentHeightChange(height)
            }
        }
        .scrollIndicators(.hidden)
        .ghafBackground(theme: theme)
        .sheet(isPresented: $editing) {
            GhafTransactionEditor(transaction: transaction, categories: settings.categories, themeName: settings.themeName,
                                  appearanceMode: settings.appearanceMode, languageCode: lang, accounts: accounts)
                .presentationDragIndicator(.visible).ghafDirection(lang)
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 18) {
            // Who and when, like a receipt's first line.
            HStack(spacing: 12) {
                GhafCategoryIcon(category: transaction.category, tint: theme.accent, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(merchantName)
                        .font(GhafTypography.userContent(merchantName, size: 17, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(transactionDateLabel)
                        .font(GhafTypography.body(13, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
                    ShareLink(item: receiptText) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(ar ? "مشاركة الإيصال" : "Share receipt")
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
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(status.tint.opacity(theme.isDark ? 0.22 : 0.14), in: Capsule())
                .overlay(Capsule().stroke(status.tint.opacity(0.35), lineWidth: 1))
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
                                  text: "1 \(code) = \(rate.formatted(.number.precision(.fractionLength(0...4)).locale(GhafLocale.locale(identifier: lang)))) \(transaction.currency)"
                                    + " · " + (transaction.exchangeRateDate ?? transaction.date).formatted(.dateTime.day().month().hour().minute().locale(GhafLocale.locale(identifier: lang)))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.ghafPress)
    }

    private var receiptText: String {
        let amount = (isCredit ? "+" : "-") + GhafFormat.money(transaction.amount, currency: transaction.currency, languageCode: lang)
        return [status.title, merchantName, amount,
                transaction.date.formatted(.dateTime.day().month().year().hour().minute().locale(GhafLocale.locale(identifier: lang))),
                account?.name, "#" + transaction.id.uuidString.prefix(8)]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
