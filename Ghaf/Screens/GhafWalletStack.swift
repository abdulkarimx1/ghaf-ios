import SwiftUI
import SwiftData

/// Wallet account carousel with the chosen card's balance, actions and latest purchases.
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
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
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
        }
        .sheet(item: $quickAdd) { item in
            GhafQuickAddView(settings: settings, presetAccountID: item.account, startAsTransfer: item.transfer).ghafDirection(settings.languageCode)
        }
    }

    // MARK: Cards

    /// Flat, view-aligned cards; native scrolling tracks the finger and settles on the nearest account.
    private var deck: some View {
        GhafWalletCarousel(cards: accounts.map(GhafWalletCardSnapshot.init), selectedID: $selectedID,
                          languageCode: languageCode, reduceMotion: reduceMotion, theme: theme,
                          onEdit: { id in if let account = accounts.first(where: { $0.id == id }) { onEdit(account) } },
                          onMove: { id, offset in if let account = accounts.first(where: { $0.id == id }) { onMove(account, offset) } })
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

private struct GhafWalletCardSnapshot: Identifiable {
    let id: UUID
    let name: String
    let institution: String
    let lastFour: String
    let design: GhafCardDesign?

    init(_ account: GhafAccount) {
        id = account.id
        name = account.name
        institution = account.institution ?? ""
        lastFour = account.lastFourDigits ?? ""
        design = GhafCardDesign.forAccount(account)
    }
}

private struct GhafWalletCarousel: View {
    let cards: [GhafWalletCardSnapshot]
    @Binding var selectedID: UUID?
    let languageCode: String
    let reduceMotion: Bool
    let theme: GhafTheme
    let onEdit: (UUID) -> Void
    let onMove: (UUID, Int) -> Void
    private var ar: Bool { languageCode == "ar" }
    private var index: Int { cards.firstIndex { $0.id == selectedID } ?? 0 }
    private var width: CGFloat { min(UIScreen.main.bounds.width * 0.78, 360) }
    private var cardHeight: CGFloat { width / 1.586 }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(cards) { card in walletCard(card) }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedID, anchor: .center)
            .contentMargins(.horizontal, max(0, (geometry.size.width - width) / 2), for: .scrollContent)
            .frame(height: cardHeight)
            .accessibilityElement()
            .accessibilityLabel(cards.indices.contains(index) ? cards[index].name : "")
            .accessibilityValue(ar ? "بطاقة \(index + 1) من \(cards.count)" : "Card \(index + 1) of \(cards.count)")
            .accessibilityAdjustableAction { direction in
                let next = min(max(index + (direction == .increment ? 1 : -1), 0), cards.count - 1)
                withAnimation(deckAnimation) { selectedID = cards[next].id }
            }
        }
        .onChange(of: cards.map(\.id)) { _, ids in
            if selectedID.map(ids.contains) != true { selectedID = ids.first }
        }
    }

    private func walletCard(_ card: GhafWalletCardSnapshot) -> some View {
        return GhafCardFace(account: nil, name: card.name, institution: card.institution,
                            lastFour: card.lastFour, design: card.design, width: width)
            .frame(width: width, height: cardHeight)
            .id(card.id)
            .onTapGesture { withAnimation(deckAnimation) { selectedID = card.id } }
            .contextMenu {
                Button { onEdit(card.id) } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil") }
                Button { onMove(card.id, -1) } label: { Label(ar ? "نقل للأمام" : "Move earlier", systemImage: "arrow.backward") }
                    .disabled(card.id == cards.first?.id)
                Button { onMove(card.id, 1) } label: { Label(ar ? "نقل للخلف" : "Move later", systemImage: "arrow.forward") }
                    .disabled(card.id == cards.last?.id)
            }
            .accessibilityHidden(true)
    }

    private var deckAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0 : 0.18)
    }
}
