import SwiftUI
import GhafCore

struct GhafTransactionSentenceCard: View {
    @Binding var draft: GhafVoiceTransactionDraft
    let accounts: [GhafAccount]
    let transactions: [GhafTransaction]
    let theme: GhafTheme
    let languageCode: String
    let enabled: Bool

    @State private var editing: String?
    private var ar: Bool { languageCode == "ar" }
    private var accountName: String {
        accounts.first(where: { $0.id == draft.accountID })?.name
            ?? accounts.first(where: { $0.isPrimary && !$0.isArchived })?.name
            ?? (ar ? "حساب" : "Account")
    }
    private var dateText: String {
        if Calendar.current.isDateInToday(draft.date) { return ar ? "اليوم" : "today" }
        return draft.date.formatted(.dateTime.day().month(.abbreviated).locale(GhafLocalization.locale(languageCode: languageCode)))
    }
    private var timeText: String {
        draft.date.formatted(.dateTime.hour().minute().locale(GhafLocalization.locale(languageCode: languageCode)))
    }
    private var sentence: AttributedString {
        var result = AttributedString(draft.direction == "credit" ? (ar ? "تم استلام " : "Received ") : (ar ? "تم إنفاق " : "Spent "))
        result += linked("\(draft.currency) \(draft.amountText)", field: "amount")
        result += AttributedString(ar ? " على " : " on ")
        result += linked("🍴\(GhafLocalization.category(draft.category, languageCode: languageCode))", field: "category")
        result += AttributedString(ar ? " من " : " from ")
        result += linked("🏦\(accountName)", field: "account")
        result += AttributedString(ar ? " " : " ")
        result += linked("📅\(dateText)", field: "date")
        result += AttributedString(ar ? " في " : " at ")
        result += linked("🕘\(timeText)", field: "time")
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sentence)
                .font(GhafTypography.body(17, languageCode: languageCode, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineSpacing(5)
                .environment(\.openURL, OpenURLAction { url in
                    editing = url.host
                    return .handled
                })
            if enabled, let editing {
                switch editing {
                case "amount":
                    GhafAmountField(value: $draft.amountText, currency: draft.currency,
                                    label: ar ? "المبلغ" : "Amount", theme: theme, languageCode: languageCode)
                case "category":
                    GhafCategoryPicker(category: $draft.category, subcategory: $draft.subcategory,
                                       languageCode: languageCode, tint: theme.accent)
                case "account":
                    GhafAccountPills(accounts: accounts.filter { !$0.isArchived && $0.currency == draft.currency },
                                    transactions: transactions, selection: $draft.accountID, theme: theme,
                                    languageCode: languageCode)
                case "date", "time":
                    GhafDateRow(title: ar ? "التاريخ والوقت" : "Date and time", selection: $draft.date,
                                components: editing == "date" ? [.date] : [.hourAndMinute],
                                theme: theme, languageCode: languageCode)
                default: EmptyView()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.outline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func linked(_ value: String, field: String) -> AttributedString {
        var text = AttributedString(value)
        text.link = URL(string: "ghaf-edit://\(field)")
        text.font = GhafTypography.body(17, languageCode: languageCode, weight: .bold)
        text.foregroundColor = theme.accent
        return text
    }
}
