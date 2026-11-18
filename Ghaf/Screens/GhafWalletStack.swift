import SwiftUI
import SwiftData

/// Accounts as a swipeable row of cards, one at a time with the next one peeking, like a wallet app.
/// The balance is printed on the card; round actions and the card's details sit underneath.
/// Scales to any number of cards without compressing them.
struct GhafWalletStack: View {
    let accounts: [GhafAccount]
    let balances: [UUID: Decimal]
    let transactions: [GhafTransaction]
    let settings: GhafSettings
    let theme: GhafTheme
    let onEdit: (GhafAccount) -> Void
    let onMove: (GhafAccount, Int) -> Void
    let onAdd: () -> Void

    @State private var selectedID: UUID?
    @State private var quickAdd: QuickAdd?
    private struct QuickAdd: Identifiable { let id = UUID(); let account: UUID; let transfer: Bool }

    private var languageCode: String { settings.languageCode }
    private var ar: Bool { languageCode == "ar" }
    private var current: GhafAccount? { accounts.first { $0.id == selectedID } ?? accounts.first }

    var body: some View {
        VStack(spacing: 18) {
            carousel
            if accounts.count > 1 { pageIndicator }
            if let account = current {
                actions(account)
                details(account).id(account.id).transition(.opacity)
            }
        }
        .animation(.snappy, value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
        .onAppear { if selectedID == nil { selectedID = accounts.first?.id } }
        .sheet(item: $quickAdd) { item in
            GhafQuickAddView(settings: settings, presetAccountID: item.account, startAsTransfer: item.transfer)
        }
    }

    // MARK: Cards

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(accounts) { account in
                    card(account)
                        .containerRelativeFrame(.horizontal) { width, _ in width - 2 * GhafMetrics.gutter - 16 }
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.7)
                        }
                        .contextMenu {
                            Button { onEdit(account) } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil") }
                            Button { onMove(account, -1) } label: { Label(ar ? "نقل لليسار" : "Move earlier", systemImage: "arrow.backward") }
                                .disabled(account.id == accounts.first?.id)
                            Button { onMove(account, 1) } label: { Label(ar ? "نقل لليمين" : "Move later", systemImage: "arrow.forward") }
                                .disabled(account.id == accounts.last?.id)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, GhafMetrics.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        // The row runs edge to edge; the cards keep the page's margins.
        .padding(.horizontal, -GhafMetrics.gutter)
    }

    private func card(_ account: GhafAccount) -> some View {
        GeometryReader { geometry in
            GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                         lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: geometry.size.width)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                            .lineLimit(1)
                        GhafMoneyLabel(amount: balances[account.id] ?? account.openingBalance, currency: account.currency,
                                       languageCode: languageCode, size: 26)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(
                        // A soft scrim so the balance reads on any card art.
                        LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(10)
                }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }

    private var pageIndicator: some View {
        Group {
            if accounts.count <= 8 {
                HStack(spacing: 6) {
                    ForEach(accounts) { account in
                        Capsule().fill(account.id == current?.id ? theme.accent : theme.secondaryText.opacity(0.25))
                            .frame(width: account.id == current?.id ? 20 : 7, height: 7)
                    }
                }
            } else {
                let index = (accounts.firstIndex { $0.id == current?.id } ?? 0) + 1
                Text("\(index) / \(accounts.count)")
                    .font(GhafTypography.number(13, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Actions and details

    private func actions(_ account: GhafAccount) -> some View {
        HStack(spacing: 0) {
            action(ar ? "صرف" : "Spend", "minus") { quickAdd = QuickAdd(account: account.id, transfer: false) }
            action(ar ? "تحويل" : "Transfer", "arrow.left.arrow.right") { quickAdd = QuickAdd(account: account.id, transfer: true) }
                .disabled(accounts.count < 2)
            action(ar ? "تعديل" : "Edit", "pencil") { onEdit(account) }
            action(ar ? "بطاقة" : "New card", "plus") { onAdd() }
        }
    }

    private func action(_ title: String, _ icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 56, height: 56)
                    .background(theme.surface, in: Circle())
                    .shadow(color: theme.shadow, radius: 8, y: 3)
                Text(title)
                    .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ghafPress)
    }

    private func details(_ account: GhafAccount) -> some View {
        let own = transactions.filter { $0.accountID == account.id }.sorted { $0.date > $1.date }
        let month = own.filter { GhafCalendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
        let spent = month.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        let income = month.filter(\.isIncome).reduce(Decimal.zero) { $0 + $1.amount }
        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                stat(ar ? "صرف هذا الشهر" : "Spent this month", spent, account.currency, theme.over, "arrow.down.right")
                stat(ar ? "دخل هذا الشهر" : "In this month", income, account.currency, theme.credit, "arrow.up.right")
            }
            GhafDetailCard(theme: theme) {
                GhafDetailRow(label: ar ? "النوع" : "Type", text: typeTitle(account.type), theme: theme, languageCode: languageCode)
                if let bank = account.institution, !bank.isEmpty {
                    GhafDetailRow(label: ar ? "البنك" : "Bank", text: bank, theme: theme, languageCode: languageCode)
                }
                if let lastFour = account.lastFourDigits, !lastFour.isEmpty {
                    GhafDetailRow(label: ar ? "البطاقة" : "Card", text: "•••• \(lastFour)", theme: theme, languageCode: languageCode)
                }
                GhafDetailRow(label: ar ? "العملة" : "Currency", text: account.currency, theme: theme, languageCode: languageCode, divider: false)
            }
            if !own.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ar ? "آخر العمليات" : "Recent activity")
                        .font(GhafTypography.heading(18, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
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
            }
        }
    }

    private func stat(_ title: String, _ value: Decimal, _ currency: String, _ tint: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(tint)
            GhafMoneyLabel(amount: value, currency: currency, languageCode: languageCode, size: 18)
                .foregroundStyle(theme.primaryText)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme, radius: 18)
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
