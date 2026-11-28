import SwiftUI
import GhafCore

private struct SentenceField: Identifiable { let id: String }

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
    private var sentence: Text {
        helper(ar ? (draft.direction == "credit" ? "استلمت " : "صرفت ") : (draft.direction == "credit" ? "Received " : "Spent ")) +
        GhafMoneyText.text("\(draft.currency) \(draft.amountText)", size: 26, link: URL(string: "ghaf-edit://amount"))
            .font(GhafTypography.body(26, languageCode: languageCode, weight: .bold))
            .foregroundColor(theme.primaryText)
        + helper(ar ? " على " : " on ") + linked(GhafLocalization.category(draft.category, languageCode: languageCode), field: "category", symbol: "fork.knife")
        + helper(ar ? " من " : " from ") + linked(accountName, field: "account", symbol: "building.columns")
        + Text(" ") + linked(dateText, field: "date", symbol: "calendar")
        + helper(ar ? " في " : " at ") + linked(timeText, field: "time", symbol: "clock")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sentence
                .font(GhafTypography.body(26, languageCode: languageCode, weight: .regular))
                .foregroundStyle(theme.primaryText)
                .lineSpacing(4)
                .environment(\.openURL, OpenURLAction { url in
                    editing = url.host
                    return .handled
                })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.outline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .sheet(item: Binding(get: { enabled ? editing.map(SentenceField.init) : nil }, set: { editing = $0?.id })) { field in
            VStack(spacing: 16) {
                switch field.id {
                case "amount":
                    GhafAmountField(value: $draft.amountText, currency: draft.currency, label: ar ? "المبلغ" : "Amount", theme: theme, languageCode: languageCode)
                case "category":
                    GhafCategoryPicker(category: $draft.category, subcategory: $draft.subcategory, languageCode: languageCode, tint: theme.accent)
                case "account":
                    GhafAccountPills(accounts: accounts.filter { !$0.isArchived && $0.currency == draft.currency }, transactions: transactions,
                                    selection: $draft.accountID, theme: theme, languageCode: languageCode)
                case "date":
                    DatePicker(ar ? "التاريخ" : "Date", selection: $draft.date, displayedComponents: [.date]).datePickerStyle(.graphical).tint(theme.accent)
                case "time":
                    DatePicker(ar ? "الوقت" : "Time", selection: $draft.date, displayedComponents: [.hourAndMinute]).datePickerStyle(.wheel).tint(theme.accent)
                default: EmptyView()
                }
                Button(ar ? "تم" : "Done") { editing = nil }
                    .ghafProminentButton(theme: theme, languageCode: languageCode)
            }
            .padding(20).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .ghafBottomCard(theme: theme, languageCode: languageCode).ghafDirection(languageCode)
        }
    }

    private func linked(_ value: String, field: String, symbol: String? = nil) -> Text {
        var text = AttributedString(value)
        text.link = URL(string: "ghaf-edit://\(field)")
        text.font = GhafTypography.body(26, languageCode: languageCode, weight: .bold)
        text.foregroundColor = theme.primaryText
        guard let symbol else { return Text(text) }
        return Text(Image(systemName: symbol)).font(GhafTypography.body(22, languageCode: languageCode)) + Text(text)
    }

    private func helper(_ value: String) -> Text { Text(value).foregroundColor(theme.secondaryText) }
}
