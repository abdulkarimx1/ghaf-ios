import SwiftUI
import SwiftData

/// Accounts as an Apple Pay style deck (canvas "Wallet"): the chosen card's balance on top, the card in front
/// with its neighbours peeking, dots, four round actions and the card's latest purchases.
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

    private var index: Int { accounts.firstIndex { $0.id == current?.id } ?? 0 }

    var body: some View {
        VStack(spacing: 18) {
            if let account = current {
                // "<card> balance" over a big number, like the canvas; the card itself stays clean.
                VStack(spacing: 2) {
                    Text(ar ? "رصيد \(account.name)" : "\(account.name) balance")
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                    GhafMoneyLabel(amount: balances[account.id] ?? account.openingBalance, currency: account.currency,
                                   languageCode: languageCode, size: 40)
                        .foregroundStyle(theme.primaryText)
                        .contentTransition(.numericText())
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
            deck
            if accounts.count > 1 { pageIndicator }
            if let account = current {
                actions(account)
                recent(account).id(account.id).transition(.opacity)
            }
        }
        .animation(.snappy, value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
        .onAppear { if selectedID == nil { selectedID = accounts.first?.id } }
        .sheet(item: $quickAdd) { item in
            GhafQuickAddView(settings: settings, presetAccountID: item.account, startAsTransfer: item.transfer).ghafDirection(settings.languageCode)
        }
    }

    // MARK: Cards

    @State private var drag: CGFloat = 0

    /// Apple Pay style: the chosen card in front, its neighbours tucked behind and peeking on each side.
    private var deck: some View {
        // Canvas: a 250pt card on a 390pt screen, neighbours shifted 52pt and scaled to 0.86.
        let width = min((UIScreen.main.bounds.width) * 0.64, 300)
        let step = width * 0.208
        // SwiftUI mirrors offsets in Arabic but drag translations stay physical, so only the drag is flipped.
        let sign: CGFloat = ar ? -1 : 1
        return ZStack {
            Ellipse()
                .fill(theme.accent.opacity(0.55))
                .frame(width: width * 0.8, height: 60)
                .blur(radius: 22)
                .offset(y: width / 1.586 / 2 + 6)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { k, account in
                let d = k - index
                if abs(d) <= 2 {
                    GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                                 lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: width)
                        .brightness(d == 0 ? 0 : -0.14)
                        .scaleEffect(d == 0 ? 1 : 0.86)
                        .offset(x: CGFloat(d) * step + sign * drag)
                        .opacity(abs(d) > 1 ? 0 : 1)
                        .zIndex(Double(10 - abs(d)))
                        .onTapGesture { selectedID = account.id }
                        .contextMenu {
                            Button { onEdit(account) } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil") }
                            Button { onMove(account, -1) } label: { Label(ar ? "نقل للأمام" : "Move earlier", systemImage: "arrow.backward") }
                                .disabled(account.id == accounts.first?.id)
                            Button { onMove(account, 1) } label: { Label(ar ? "نقل للخلف" : "Move later", systemImage: "arrow.forward") }
                                .disabled(account.id == accounts.last?.id)
                        }
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: width / 1.586 + 50)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.width * 0.6 }
                .onEnded { value in
                    let move = sign * value.predictedEndTranslation.width
                    var next = index
                    if move < -step { next = min(index + 1, accounts.count - 1) }
                    if move > step { next = max(index - 1, 0) }
                    withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                        selectedID = accounts[next].id
                        drag = 0
                    }
                }
        )
        .animation(.spring(duration: 0.45, bounce: 0.2), value: selectedID)
        .accessibilityElement()
        .accessibilityLabel(current?.name ?? "")
        .accessibilityValue(ar ? "بطاقة \(index + 1) من \(accounts.count)" : "Card \(index + 1) of \(accounts.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selectedID = accounts[min(index + 1, accounts.count - 1)].id
            case .decrement: selectedID = accounts[max(index - 1, 0)].id
            @unknown default: break
            }
        }
    }

    private var pageIndicator: some View {
        Group {
            if accounts.count <= 12 {
                HStack(spacing: 6) {
                    ForEach(accounts) { account in
                        Capsule().fill(account.id == current?.id ? theme.primaryText : theme.secondaryText.opacity(0.25))
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

    private func recent(_ account: GhafAccount) -> some View {
        let own = transactions.filter { $0.accountID == account.id }.sorted { $0.date > $1.date }.prefix(3)
        return Group {
            if !own.isEmpty {
                VStack(spacing: 0) {
                    ForEach(own, id: \.id) { item in
                        GhafTransactionRow(transaction: item, theme: theme, languageCode: languageCode)
                            .frame(minHeight: 58)
                        if item.id != own.last?.id { Divider().overlay(theme.outline).padding(.leading, 58) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .ghafCard(theme: theme, radius: 22)
            }
        }
    }
}
