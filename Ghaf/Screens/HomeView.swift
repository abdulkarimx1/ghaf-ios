import SwiftUI
import SwiftData
import GhafCore

struct GhafHomeView: View {

    @Environment(\.colorScheme) private var systemColorScheme

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @State private var showQuickAdd = false

    let settings: GhafSettings

    private var theme: GhafTheme {

        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var snapshot: BudgetSnapshot {

        BudgetCalculator.snapshot(
            settings: settings,
            transactions: transactions
        )
    }

    private var todayTransactions: [GhafTransaction] {

        transactions.filter {
            Calendar.current.isDate(
                $0.date,
                inSameDayAs: Date()
            )
        }
    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(alignment: .leading, spacing: 24) {

                    header

                    budgetCard

                    quickAddButton

                    todaySection
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarHidden(true)
            .sheet(isPresented: $showQuickAdd) {

                GhafQuickAddView(settings: settings)
            }
        }
    }

    private var header: some View {

        HStack(alignment: .center) {

            VStack(alignment: .leading, spacing: 5) {

                Text(greeting)
                    .font(GhafTypeScale.caption)
                    .tracking(1.5)
                    .foregroundStyle(theme.secondaryText)

                Text(
                    settings.userName.isEmpty
                        ? "Welcome to Ghaf"
                        : "Hello, \(settings.userName)"
                )
                .font(GhafTypeScale.title)
                .foregroundStyle(theme.primaryText)

                Text(Date.now.formatted(
                    .dateTime.weekday(.wide).month(.abbreviated).day()
                ))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            GhafTreeMark(color: theme.accent)
                .frame(width: 54, height: 54)
        }
    }

    private var greeting: String {

        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )

        if settings.languageCode == "ar" {
            return hour < 17 ? "صباح الخير" : "مساء الخير"
        }
        if hour < 12 {
            return "GOOD MORNING"
        } else if hour < 17 {
            return "GOOD AFTERNOON"
        } else {
            return "GOOD EVENING"
        }
    }

    private var budgetCard: some View {

        VStack(alignment: .leading, spacing: 22) {

            HStack {

                VStack(alignment: .leading, spacing: 6) {

                    Text(snapshot.periodTitle.uppercased())
                        .font(GhafTypeScale.caption)
                        .tracking(1.3)
                        .foregroundStyle(theme.accentContrast.opacity(0.75))

                    Text(
                        snapshot.hasBudget
                            ? GhafFormat.money(
                                snapshot.remaining,
                                currency: settings.currency
                            )
                            : "Set your budget"
                    )
                    .font(
                        .system(
                            size: snapshot.hasBudget ? 36 : 27,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(theme.accentContrast)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                }

                Spacer()

                BudgetRing(
                    progress: snapshot.progress,
                    statusColor: theme.statusColor(snapshot.status),
                    trackColor: theme.accentContrast.opacity(0.20)
                )
                .frame(width: 76, height: 76)
            }

            Rectangle()
                .fill(theme.accentContrast.opacity(0.20))
                .frame(height: 1)

            HStack {

                budgetMetric(
                    title: "BUDGET",
                    amount: snapshot.limit
                )

                Spacer()

                budgetMetric(
                    title: "SPENT",
                    amount: snapshot.spent
                )

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {

                    Text("STATUS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(theme.accentContrast.opacity(0.70))

                    Text(statusTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.statusColor(snapshot.status))
                }
            }

            if !snapshot.hasBudget {

                Text(
                    settings.budgetMode == "Category"
                        ? "Add category budgets in Settings."
                        : "Add your monthly income in Settings."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.accentContrast.opacity(0.8))
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [theme.accent, theme.accent.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: theme.accent.opacity(0.18), radius: 20, y: 10)
    }

    private var statusTitle: String {

        if settings.languageCode == "ar" {
            switch snapshot.status {
            case .comfortable: return "ضمن الميزانية"
            case .close: return "اقتربت من الحد"
            case .over: return "تجاوزت الميزانية"
            }
        }
        switch snapshot.status {
        case .comfortable:
            return "Comfortable"
        case .close:
            return "Close"
        case .over:
            return "Over budget"
        }
    }

    private func budgetMetric(
        title: String,
        amount: Decimal
    ) -> some View {

        VStack(alignment: .leading, spacing: 5) {

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.accentContrast.opacity(0.70))

            Text(
                GhafFormat.money(
                    amount,
                    currency: settings.currency
                )
            )
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.accentContrast)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        }
    }

    private var quickAddButton: some View {

        Button {
            showQuickAdd = true
        } label: {

            HStack(spacing: 12) {

                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .bold))

                Text("Add transaction")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(theme.primaryText)
            .padding(18)
        }
        .buttonStyle(GhafGlassButtonStyle(theme: theme))
    }

    private var todaySection: some View {

        VStack(alignment: .leading, spacing: 14) {

            HStack {

                Text("Today's activity")
                    .font(GhafTypeScale.title)
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("\(todayTransactions.count) transactions")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }

            if todayTransactions.isEmpty {

                VStack(spacing: 10) {

                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundStyle(theme.secondaryText)

                    Text("No transactions yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("Your activity will appear here.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .ghafGlass(theme: theme, radius: 22)

            } else {

                VStack(spacing: 0) {

                    ForEach(
                        Array(todayTransactions.prefix(8)),
                        id: \.id
                    ) { transaction in

                        GhafTransactionRow(
                            transaction: transaction,
                            theme: theme
                        )

                        if transaction.id != todayTransactions.prefix(8).last?.id {
                            Divider()
                                .overlay(theme.outline)
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    theme.surface,
                    in: RoundedRectangle(cornerRadius: 20)
                )
            }
        }
    }
}

// MARK: - Budget Ring

struct BudgetRing: View {

    let progress: Double
    let statusColor: Color
    let trackColor: Color

    var body: some View {

        ZStack {

            Circle()
                .stroke(
                    trackColor,
                    lineWidth: 8
                )

            Circle()
                .trim(
                    from: 0,
                    to: progress
                )
                .stroke(
                    statusColor,
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Transaction Row

struct GhafTransactionRow: View {

    let transaction: GhafTransaction
    let theme: GhafTheme

    var body: some View {

        HStack(spacing: 13) {

            GhafCategoryIcon(category: transaction.category, tint: theme.accent)

            VStack(alignment: .leading, spacing: 4) {

                Text(
                    transaction.merchant?.isEmpty == false
                        ? transaction.merchant!
                        : transaction.category
                )
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

                Text(
                    "\(transaction.category) · \(transaction.date.formatted(date: .omitted, time: .shortened))"
                )
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {

                Text(amountText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        transaction.direction == "credit"
                            ? theme.credit
                            : theme.primaryText
                    )

                if transaction.needsReview {

                    Text("REVIEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.close)
                }
            }
        }
        .padding(.vertical, 13)
    }

    private var amountText: String {

        let prefix = transaction.direction == "credit"
            ? "+"
            : "−"

        return prefix + GhafFormat.money(
            transaction.amount,
            currency: transaction.currency
        )
    }

    private var iconName: String {

        switch transaction.category {

        case "Groceries":
            return "basket"

        case "Dining":
            return "fork.knife"

        case "Transport":
            return "car"

        case "Fuel":
            return "fuelpump"

        case "Bills & Utilities":
            return "bolt"

        case "Shopping":
            return "bag"

        case "Health":
            return "cross.case"

        case "Entertainment":
            return "play.rectangle"

        case "Travel":
            return "airplane"

        case "Salary":
            return "banknote"

        case "Transfers":
            return "arrow.left.arrow.right"

        default:
            return "creditcard"
        }
    }
}

// MARK: - Quick Add

struct GhafQuickAddView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let settings: GhafSettings

    @State private var amount = ""
    @State private var merchant = ""
    @State private var category = "Other"
    @State private var direction = "debit"
    @State private var note = ""
    @State private var date = Date()

    @State private var errorMessage = ""

    var body: some View {

        NavigationStack {

            Form {

                Section("Transaction") {

                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)

                    TextField("Merchant", text: $merchant)

                    Picker("Type", selection: $direction) {
                        Text("Expense").tag("debit")
                        Text("Income").tag("credit")
                    }

                    Picker("Category", selection: $category) {
                        ForEach(settings.categories, id: \.self) {
                            Text($0).tag($0)
                        }
                    }

                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Note") {

                    TextField("Optional note", text: $note)
                }

                if !errorMessage.isEmpty {

                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func save() {

        guard let value = Decimal(string: amount),
              value > 0 else {

            errorMessage = "Enter a valid amount."
            return
        }

        let parsed = ParsedTransaction(
            amount: value,
            currency: settings.currency,
            merchant: merchant.isEmpty ? nil : merchant,
            date: date,
            direction: TransactionDirection(
                rawValue: direction
            ) ?? .debit,
            confidence: 1.0,
            bank: nil
        )

        let transaction = GhafTransaction(
            fingerprint: "manual-\(UUID().uuidString)",
            parsed: parsed,
            category: category,
            needsReview: false,
            isReversal: false
        )

        transaction.note = note

        modelContext.insert(transaction)

        do {

            try modelContext.save()
            dismiss()

        } catch {

            errorMessage = "Could not save transaction."
        }
    }
}
