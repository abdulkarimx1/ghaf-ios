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

    /// Apple Pay style: the chosen card in front, its neighbours tucked behind and peeking on each side.
    private var deck: some View {
        GhafWalletCarousel(accounts: accounts, selectedID: $selectedID, languageCode: languageCode,
                          reduceMotion: reduceMotion, theme: theme, onEdit: onEdit, onMove: onMove)
            .padding(.horizontal, -GhafMetrics.gutter)
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
        return VStack(spacing: 0) {
            if !own.isEmpty {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        if own.indices.contains(index) {
                            let item = own[index]
                        GhafTransactionRow(transaction: item, theme: theme, languageCode: languageCode)
                            .frame(minHeight: 58)
                            if index < 2 { Divider().overlay(theme.outline).padding(.leading, 58) }
                        } else {
                            Color.clear.frame(height: 58)
                        }
                    }
                }
            } else {
                Text(ar ? "لا توجد عمليات بعد" : "No transactions yet")
                    .font(GhafTypography.body(14, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 174)
            }
        }
        .frame(height: 186)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .ghafCard(theme: theme, radius: 22)
    }
}

/// Owns high-frequency drag state so swiping doesn't reevaluate the balance and transaction rows.
private struct GhafWalletCarousel: View {
    let accounts: [GhafAccount]
    @Binding var selectedID: UUID?
    let languageCode: String
    let reduceMotion: Bool
    let theme: GhafTheme
    let onEdit: (GhafAccount) -> Void
    let onMove: (GhafAccount, Int) -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var dragOriginIndex: Int?
    @State private var dragStartX: CGFloat?
    @State private var positionRecorder = GhafWalletOffsetRecorder()
    private var ar: Bool { languageCode == "ar" }
    private var index: Int { accounts.firstIndex { $0.id == selectedID } ?? 0 }
    private var width: CGFloat { max(240, UIScreen.main.bounds.width) }
    private var cardHeight: CGFloat { width / 1.586 }
    private var step: CGFloat { width * 0.6 }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(theme.accent.opacity(0.55))
                .frame(width: width * 0.8, height: 60)
                .blur(radius: 22)
                .offset(y: cardHeight / 2 + 6)
            GeometryReader { geometry in
                let restingOffset = (geometry.size.width - width) / 2 - CGFloat(index) * step
                let baseIndex = dragOriginIndex ?? index
                let baseOffset = (geometry.size.width - width) / 2 - CGFloat(baseIndex) * step
                HStack(spacing: -width * 0.4) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { itemIndex, account in
                        walletCard(account, at: itemIndex)
                    }
                }
                .modifier(GhafWalletTrackedOffset(value: baseOffset + dragOffset, recorder: positionRecorder))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if dragOriginIndex == nil {
                            dragOriginIndex = index
                            dragStartX = positionRecorder.value
                        }
                        dragOffset = (dragStartX ?? restingOffset) - baseOffset + value.translation.width
                    }
                    .onEnded { value in
                        let origin = dragOriginIndex ?? index
                        let travel = value.predictedEndTranslation.width
                        let moved = Int((-travel / step).rounded())
                        let next = min(max(origin + moved, 0), accounts.count - 1)
                        let startX = dragStartX ?? ((geometry.size.width - width) / 2 - CGFloat(origin) * step)
                        let predictedX = startX + travel
                        let targetOffset = (geometry.size.width - width) / 2 - CGFloat(next) * step
                        withTransaction(Transaction(animation: nil)) {
                            selectedID = accounts[next].id
                            dragOriginIndex = nil
                            dragStartX = nil
                            dragOffset = predictedX - targetOffset
                        }
                        DispatchQueue.main.async {
                            withAnimation(deckAnimation) { dragOffset = 0 }
                        }
                    })
            }
            .frame(height: cardHeight + 50)
            .clipped()
        }
            .accessibilityElement()
            .accessibilityLabel(accounts.indices.contains(index) ? accounts[index].name : "")
            .accessibilityValue(ar ? "بطاقة \(index + 1) من \(accounts.count)" : "Card \(index + 1) of \(accounts.count)")
            .accessibilityAdjustableAction { direction in
                let next = min(max(index + (direction == .increment ? 1 : -1), 0), accounts.count - 1)
                withAnimation(deckAnimation) { selectedID = accounts[next].id }
            }
    }

    private func walletCard(_ account: GhafAccount, at itemIndex: Int) -> some View {
        let delta = itemIndex - index
        return GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                            lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: width)
            .scaleEffect(delta == 0 ? 1 : 0.9, anchor: .center)
            .zIndex(Double(-abs(delta)))
            .frame(width: width, height: cardHeight)
            .frame(width: width, height: cardHeight + 50)
            .id(account.id)
            .onTapGesture { withAnimation(deckAnimation) { selectedID = account.id } }
            .contextMenu {
                Button { onEdit(account) } label: { Label(ar ? "تعديل" : "Edit", systemImage: "pencil") }
                Button { onMove(account, -1) } label: { Label(ar ? "نقل للأمام" : "Move earlier", systemImage: "arrow.backward") }
                    .disabled(account.id == accounts.first?.id)
                Button { onMove(account, 1) } label: { Label(ar ? "نقل للخلف" : "Move later", systemImage: "arrow.forward") }
                    .disabled(account.id == accounts.last?.id)
            }
            .accessibilityHidden(true)
    }

    private var deckAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0 : 0.18)
    }
}

/// Reads SwiftUI's presentation value during settling without invalidating the carousel every frame.
private final class GhafWalletOffsetRecorder {
    var value: CGFloat = 0
}

private struct GhafWalletTrackedOffset: AnimatableModifier {
    var value: CGFloat
    let recorder: GhafWalletOffsetRecorder

    var animatableData: CGFloat {
        get { value }
        set {
            value = newValue
            recorder.value = newValue
        }
    }

    func body(content: Content) -> some View {
        content.offset(x: value)
    }
}
