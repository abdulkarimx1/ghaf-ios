import SwiftUI
import SwiftData

/// Accounts as an Apple Pay style deck (canvas "Wallet"): the chosen card's balance on top, the card in front
/// with its neighbours peeking, dots, four round actions and the card's latest purchases.
struct GhafWalletStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accounts: [GhafAccount]
    let balances: [UUID: Decimal]
    let transactions: [GhafTransaction]
    let settings: GhafSettings
    let theme: GhafTheme
    let onEdit: (GhafAccount) -> Void
    let onMove: (GhafAccount, Int) -> Void
    let onAdd: () -> Void

    @State private var selectedID: UUID?
    @State private var deckPosition = 0.0
    @State private var dragStartPosition = 0.0
    @State private var isDragging = false
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
        .sensoryFeedback(.selection, trigger: selectedID)
        .onAppear {
            if selectedID == nil { selectedID = accounts.first?.id }
            deckPosition = Double(index)
        }
        .sheet(item: $quickAdd) { item in
            GhafQuickAddView(settings: settings, presetAccountID: item.account, startAsTransfer: item.transfer).ghafDirection(settings.languageCode)
        }
    }

    // MARK: Cards

    /// Apple Pay style: the chosen card in front, its neighbours tucked behind and peeking on each side.
    private var deck: some View {
        // Canvas: a 250pt card on a 390pt screen, neighbours shifted 52pt and scaled to 0.86.
        let width = min((UIScreen.main.bounds.width) * 0.64, 300)
        let step = width * 0.208
        let sign: CGFloat = ar ? -1 : 1
        return ZStack {
            Ellipse()
                .fill(theme.accent.opacity(0.55))
                .frame(width: width * 0.8, height: 60)
                .blur(radius: 22)
                .offset(y: width / 1.586 / 2 + 6)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { k, account in
                let d = Double(k) - deckPosition
                if abs(d) < 3.5 {
                    let distance = abs(d)
                    let front = distance < 1
                    let stackDistance = min(distance, 3)
                    GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                                 lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: width)
                        .brightness(front ? 0 : -0.14)
                        .scaleEffect(1 - 0.06 * stackDistance)
                        .rotationEffect(.degrees(front ? 4 * d : 0))
                        .offset(x: front ? CGFloat(-d) * step : CGFloat(d.sign == .minus ? -1 : 1) * 18 * CGFloat(stackDistance))
                        .opacity(1 - 0.25 * max(distance - 2, 0))
                        .zIndex(10 - distance)
                        .onTapGesture {
                            withAnimation(deckAnimation) { deckPosition = Double(k); selectedID = account.id }
                        }
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if !isDragging { isDragging = true; dragStartPosition = Double(index) }
                    let position = dragStartPosition - Double(sign * value.translation.width / step)
                    let high = Double(max(accounts.count - 1, 0))
                    deckPosition = position < 0 ? -abs(position) / (1 + abs(position) * 3) : position > high ? high + (position - high) / (1 + (position - high) * 3) : position
                    let visibleIndex = min(max(Int(deckPosition.rounded()), 0), accounts.count - 1)
                    selectedID = accounts[visibleIndex].id
                }
                .onEnded { value in
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                    let velocity = Double(sign * (value.predictedEndTranslation.width - value.translation.width) / step)
                    let target = isHorizontal ? min(max(Int((deckPosition - velocity * 0.35).rounded()), 0), accounts.count - 1) : index
                    withAnimation(deckAnimation) {
                        deckPosition = Double(target)
                        if accounts.indices.contains(target) { selectedID = accounts[target].id }
                    }
                    isDragging = false
                }
        )
        .accessibilityElement()
        .accessibilityLabel(current?.name ?? "")
        .accessibilityValue(ar ? "بطاقة \(index + 1) من \(accounts.count)" : "Card \(index + 1) of \(accounts.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: withAnimation(deckAnimation) { deckPosition = Double(min(index + 1, accounts.count - 1)); selectedID = accounts[min(index + 1, accounts.count - 1)].id }
            case .decrement: withAnimation(deckAnimation) { deckPosition = Double(max(index - 1, 0)); selectedID = accounts[max(index - 1, 0)].id }
            @unknown default: break
            }
        }
    }

    private var deckAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .interpolatingSpring(stiffness: 260, damping: 26)
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
                    .ghafGlassShape(theme: theme, shape: Circle(), fallback: theme.surface)
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
