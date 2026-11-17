import SwiftUI
import SwiftData

/// Accounts as a deck of cards, like Wallet: each card shows its top band and balance; tapping one
/// lifts it to the top, tucks the rest behind it, and shows its balance, details and recent activity.
struct GhafWalletStack: View {
    let accounts: [GhafAccount]
    let balances: [UUID: Decimal]
    let transactions: [GhafTransaction]
    let theme: GhafTheme
    let languageCode: String
    let onEdit: (GhafAccount) -> Void
    let onMove: (GhafAccount, Int) -> Void

    @State private var selectedID: UUID?
    @State private var width: CGFloat = 360

    private let band: CGFloat = 64      // visible top of each card in the deck
    private let tucked: CGFloat = 10    // visible edge of each card tucked behind the selected one
    private var ar: Bool { languageCode == "ar" }
    private var cardHeight: CGFloat { width / 1.586 }
    private var selectedIndex: Int? { accounts.firstIndex { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 22) {
            deck
            if let index = selectedIndex {
                details(accounts[index])
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    // MARK: Deck

    private var deckHeight: CGFloat {
        guard !accounts.isEmpty else { return 0 }
        if selectedIndex != nil { return cardHeight + CGFloat(accounts.count - 1) * tucked + 6 }
        return cardHeight + CGFloat(accounts.count - 1) * band
    }

    private func offset(_ index: Int) -> CGFloat {
        guard let selected = selectedIndex else { return CGFloat(index) * band }
        if index == selected { return 0 }
        let behind = index < selected ? index : index - 1
        return CGFloat(behind + 1) * tucked + 6
    }

    private var deck: some View {
        ZStack(alignment: .top) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                card(account)
                    .scaleEffect(selectedIndex != nil && index != selectedIndex ? 0.94 : 1, anchor: .top)
                    .offset(y: offset(index))
                    .zIndex(index == selectedIndex ? 100 : Double(selectedIndex == nil ? index : -index))
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.5, bounce: 0.18)) {
                            selectedID = selectedID == account.id ? nil : account.id
                        }
                    }
                    .contextMenu {
                        Button { onEdit(account) } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil") }
                        Button { onMove(account, -1) } label: { Label(ar ? "نقل للأعلى" : "Move up", systemImage: "arrow.up") }
                            .disabled(index == 0)
                        Button { onMove(account, 1) } label: { Label(ar ? "نقل للأسفل" : "Move down", systemImage: "arrow.down") }
                            .disabled(index == accounts.count - 1)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(ar ? "يعرض الرصيد والتفاصيل" : "Shows balance and details")
            }
        }
        .frame(height: deckHeight, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private func card(_ account: GhafAccount) -> some View {
        GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                     lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: width)
            .overlay(alignment: .topTrailing) {
                // Name and balance sit in the band that stays visible in the deck; the card art stays clean.
                VStack(alignment: .trailing, spacing: 0) {
                    Text(account.name)
                        .font(GhafTypography.body(11, languageCode: languageCode, weight: .semibold))
                        .lineLimit(1)
                        .opacity(0.85)
                    GhafMoneyLabel(amount: balances[account.id] ?? account.openingBalance, currency: account.currency,
                                   languageCode: languageCode, size: 15)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(10)
                .frame(maxWidth: width * 0.62, alignment: .trailing)
            }
    }

    // MARK: Details of the lifted card

    private func details(_ account: GhafAccount) -> some View {
        let own = transactions.filter { $0.accountID == account.id }.sorted { $0.date > $1.date }
        let month = own.filter { GhafCalendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
        let spent = month.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        let income = month.filter(\.isIncome).reduce(Decimal.zero) { $0 + $1.amount }
        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(ar ? "الرصيد" : "Balance")
                    .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                GhafMoneyLabel(amount: balances[account.id] ?? account.openingBalance, currency: account.currency,
                               languageCode: languageCode, size: 40)
                    .foregroundStyle(theme.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
                HStack(spacing: 14) {
                    Label { GhafMoneyLabel(amount: spent, currency: account.currency, languageCode: languageCode, size: 14) }
                        icon: { Image(systemName: "arrow.down.right") }
                        .foregroundStyle(theme.over)
                    Label { GhafMoneyLabel(amount: income, currency: account.currency, languageCode: languageCode, size: 14) }
                        icon: { Image(systemName: "arrow.up.right") }
                        .foregroundStyle(theme.credit)
                }
                .font(.system(size: 13, weight: .bold))
                .environment(\.layoutDirection, .leftToRight)
                Text(ar ? "هذا الشهر" : "This month")
                    .font(GhafTypography.body(12, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)

            GhafDetailCard(theme: theme) {
                GhafDetailRow(label: ar ? "النوع" : "Type", text: typeTitle(account.type), theme: theme, languageCode: languageCode)
                if let bank = account.institution, !bank.isEmpty {
                    GhafDetailRow(label: ar ? "البنك" : "Bank", text: bank, theme: theme, languageCode: languageCode)
                }
                if let lastFour = account.lastFourDigits, !lastFour.isEmpty {
                    GhafDetailRow(label: ar ? "البطاقة" : "Card", text: "•••• \(lastFour)", theme: theme, languageCode: languageCode)
                }
                if let limit = account.creditLimit {
                    GhafDetailRow(label: ar ? "الحد الائتماني" : "Credit limit", theme: theme, languageCode: languageCode) {
                        GhafMoneyLabel(amount: limit, currency: account.currency, languageCode: languageCode, size: 15)
                    }
                }
                GhafDetailRow(label: ar ? "العملة" : "Currency", text: account.currency, theme: theme, languageCode: languageCode)
                GhafDetailRow(label: ar ? "الرصيد الافتتاحي" : "Opening balance", theme: theme, languageCode: languageCode, divider: false) {
                    GhafMoneyLabel(amount: account.openingBalance, currency: account.currency, languageCode: languageCode, size: 15)
                }
            }

            if !own.isEmpty {
                VStack(spacing: 0) {
                    ForEach(own.prefix(5), id: \.id) { item in
                        GhafTransactionRow(transaction: item, theme: theme, languageCode: languageCode)
                            .padding(.vertical, 4)
                        if item.id != own.prefix(5).last?.id { Divider().overlay(theme.outline).padding(.leading, 58) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .ghafCard(theme: theme)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(duration: 0.5, bounce: 0.18)) { selectedID = nil }
                } label: { Text(ar ? "كل البطاقات" : "All cards").frame(maxWidth: .infinity) }
                .ghafGlassButton(theme: theme, languageCode: languageCode)
                Button { onEdit(account) } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                    .ghafProminentButton(theme: theme, languageCode: languageCode)
            }
        }
    }

    private func typeTitle(_ type: GhafAccountType) -> String {
        guard ar else { return type.titleKey }
        switch type {
        case .cash: return "محفظة نقدية"
        case .debit: return "بطاقة خصم"
        case .current: return "حساب جاري"
        case .savings: return "حساب توفير"
        case .credit: return "بطاقة ائتمان"
        case .prepaid: return "بطاقة مسبقة الدفع"
        }
    }
}
