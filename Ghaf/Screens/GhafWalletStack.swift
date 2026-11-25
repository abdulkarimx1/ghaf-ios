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
    @State private var allFor: GhafAccount?
    private struct QuickAdd: Identifiable { let id = UUID(); let account: UUID; let transfer: Bool }

    private var languageCode: String { settings.languageCode }
    private var ar: Bool { languageCode == "ar" }
    private var current: GhafAccount? { accounts.first { $0.id == selectedID } ?? accounts.first }

    private var index: Int { accounts.firstIndex { $0.id == current?.id } ?? 0 }

    var body: some View {
        VStack(spacing: 18) {
            totals
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
        .sheet(item: $allFor) { account in
            GhafTransactionListSheet(title: account.name, transactions: transactions.filter { $0.accountID == account.id },
                                     theme: theme, languageCode: languageCode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .ghafSheetFrame(theme: theme)
                .ghafDirection(languageCode)
        }
        .sheet(item: $quickAdd) { item in
            GhafQuickAddView(settings: settings, presetAccountID: item.account, startAsTransfer: item.transfer).ghafDirection(settings.languageCode)
        }
    }

    /// V15: one line per currency, never converted or added across currencies.
    private var totals: some View {
        let included = accounts.filter(\.includeInTotal)
        let byCurrency = Dictionary(grouping: included, by: \.currency)
            .map { (currency: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + (balances[$1.id] ?? $1.openingBalance) }) }
            .sorted { $0.currency == settings.currency ? true : ($1.currency == settings.currency ? false : $0.currency < $1.currency) }
        return VStack(spacing: 4) {
            Text(ar ? "الإجمالي" : "Total")
                .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            ForEach(byCurrency, id: \.currency) { line in
                GhafMoneyLabel(amount: line.amount, currency: line.currency, languageCode: languageCode,
                               size: line.currency == byCurrency.first?.currency ? 22 : 17)
                    .foregroundStyle(theme.primaryText)
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Cards

    /// Apple Pay style: the chosen card in front, its neighbours tucked behind and peeking on each side.
    private var deck: some View {
        GhafWalletCarousel(accounts: accounts, selectedID: $selectedID, languageCode: languageCode,
                          reduceMotion: reduceMotion, theme: theme, onEdit: onEdit, onMove: onMove)
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
                    .ghafEntrance(1)
            }
        }
        .frame(height: 186)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .ghafCard(theme: theme, radius: 22)
        .overlay(alignment: .bottom) {
            if !own.isEmpty {
                Button { allFor = account } label: {
                    Text(ar ? "عرض كل العمليات" : "View all transactions")
                        .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.ghafPress)
                .offset(y: 50)
            }
        }
        .padding(.bottom, own.isEmpty ? 0 : 44)
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
    @State private var pagePosition: CGFloat = 0
    @State private var dragStartPosition: CGFloat?
    @State private var flippedID: UUID?
    private var ar: Bool { languageCode == "ar" }
    private var index: Int { accounts.firstIndex { $0.id == selectedID } ?? 0 }

    /// Owner 1.31 pick: flat cover flow, sides at 72 % and 25 % dimmer, at most 3 cards, all inside the margins.
    private static let sideScale: CGFloat = 0.72
    static func layout(width: CGFloat) -> (card: CGFloat, step: CGFloat) {
        let step = width * 0.25
        // The side card's outer edge (step + half its scaled width) must stay inside the screen margins.
        let card = min(width * 0.86, (width / 2 - step) / (sideScale / 2))
        return (card, step)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = Self.layout(width: geometry.size.width)
            let cardWidth = size.card, step = size.step
            let cardHeight = cardWidth / 1.586
            ZStack {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { itemIndex, account in
                    let distance = CGFloat(itemIndex) - pagePosition
                    let sideAmount = min(abs(distance), 1)
                    if abs(distance) < 1.6 {
                        walletCard(account, at: itemIndex, width: cardWidth, height: cardHeight)
                            .scaleEffect(1 - sideAmount * (1 - Self.sideScale))
                            .brightness(-sideAmount * 0.25)
                            .opacity(abs(distance) > 1 ? Double(1.6 - abs(distance)) / 0.6 : 1)
                            .offset(x: distance * step) // RTL layout already mirrors this
                            .zIndex(100 - Double(abs(distance)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if dragStartPosition == nil { dragStartPosition = pagePosition; flippedID = nil }
                    let direction: CGFloat = ar ? -1 : 1
                    pagePosition = (dragStartPosition ?? pagePosition)
                        - value.translation.width * direction / (step * 1.6)
                }
                .onEnded { value in
                    let direction: CGFloat = ar ? -1 : 1
                    let start = dragStartPosition ?? pagePosition
                    let projected = start - value.predictedEndTranslation.width * direction / (step * 1.6)
                    let target = min(max(projected.rounded(), 0), CGFloat(accounts.count - 1))
                    dragStartPosition = nil
                    withAnimation(deckAnimation) {
                        pagePosition = target
                    }
                    // Keep the spring on the card deck; the balance and rows swap without riding it.
                    var selectionTransaction = Transaction()
                    selectionTransaction.disablesAnimations = true
                    withTransaction(selectionTransaction) {
                        selectedID = accounts[Int(target)].id
                    }
                })
        }
        .frame(height: Self.layout(width: min(UIScreen.main.bounds.width, 620) - 2 * GhafMetrics.gutter).card / 1.586 + 24)
            .accessibilityElement()
            .accessibilityLabel(accounts.indices.contains(index) ? accounts[index].name : "")
            .accessibilityValue(ar ? "بطاقة \(index + 1) من \(accounts.count)" : "Card \(index + 1) of \(accounts.count)")
            .accessibilityAdjustableAction { direction in
                let next = min(max(index + (direction == .increment ? 1 : -1), 0), accounts.count - 1)
                withAnimation(deckAnimation) {
                    selectedID = accounts[next].id
                    pagePosition = CGFloat(next)
                }
            }
            .onAppear { pagePosition = CGFloat(index) }
            .onChange(of: selectedID) { _, newValue in
                flippedID = nil
                guard dragStartPosition == nil,
                      let newIndex = accounts.firstIndex(where: { $0.id == newValue }) else { return }
                pagePosition = CGFloat(newIndex)
            }
    }

    private func walletCard(_ account: GhafAccount, at itemIndex: Int, width: CGFloat, height: CGFloat) -> some View {
        let flipped = flippedID == account.id
        return ZStack {
            GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                         lastFour: account.lastFourDigits ?? "", design: GhafCardDesign.forAccount(account), width: width)
                .opacity(flipped ? 0 : 1)
            cardBack(account, width: width, height: height)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .id(account.id)
        .onTapGesture {
            withAnimation(deckAnimation) {
                if account.id == selectedID || (selectedID == nil && itemIndex == 0) {
                    flippedID = flipped ? nil : account.id // tap the front card: flip to its details
                } else {
                    selectedID = account.id
                    pagePosition = CGFloat(itemIndex)
                }
            }
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

    /// The back of the card: what Ghaf knows about the account. shortcut: no IBAN field yet; add one with a schema migration if the owner wants it.
    private func cardBack(_ account: GhafAccount, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(account.displayInstitution.isEmpty ? account.name : account.displayInstitution)
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
            Spacer(minLength: 0)
            detail(ar ? "الحساب" : "Account", account.name)
            detail(ar ? "النوع" : "Type", account.type.title(languageCode: languageCode))
            detail(ar ? "العملة" : "Currency", account.currency)
            if let last = account.lastFourDigits, !last.isEmpty { detail(ar ? "آخر أربعة أرقام" : "Last four", "•••• \(last)") }
        }
        .foregroundStyle(.white)
        .padding(width * 0.07)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.30)], startPoint: .bottomLeading, endPoint: .topTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value).lineLimit(1)
        }
        .font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
    }

    private var deckAnimation: Animation {
        // Owner pick: no bounce.
        reduceMotion ? .linear(duration: 0) : .spring(response: 0.4, dampingFraction: 1)
    }
}

/// "View transactions" as a bottom card that pulls up to full screen (wallet card, stats bar).
struct GhafTransactionListSheet: View {
    let title: String
    let transactions: [GhafTransaction]
    let theme: GhafTheme
    let languageCode: String

    var body: some View {
        let own = transactions.sorted { $0.date > $1.date }
        ScrollView {
            LazyVStack(spacing: 0) {
                Text(title)
                    .font(GhafTypography.body(17, languageCode: languageCode, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .padding(.vertical, 16)
                ForEach(own) { item in
                    GhafTransactionRow(transaction: item, theme: theme, languageCode: languageCode)
                        .frame(minHeight: 58)
                    Divider().overlay(theme.outline).padding(.leading, 58)
                }
            }
            .padding(.horizontal, GhafMetrics.gutter)
        }
        .background(theme.background)
    }
}
