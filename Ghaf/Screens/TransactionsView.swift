import SwiftUI
import SwiftData

struct GhafTransactionsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @State private var searchText = ""
    @State private var filter = "All"

    @State private var selectedTransaction: GhafTransaction?
    @State private var showEditor = false

    let settings: GhafSettings

    private var theme: GhafTheme {

        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var filteredTransactions: [GhafTransaction] {

        transactions.filter { transaction in

            let matchesFilter: Bool

            switch filter {

            case "Expenses":
                matchesFilter = transaction.direction == "debit"

            case "Income":
                matchesFilter = transaction.direction == "credit"

            case "Review":
                matchesFilter = transaction.needsReview

            default:
                matchesFilter = true
            }

            let query = searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            let matchesSearch = query.isEmpty ||
                (transaction.merchant ?? "")
                    .localizedCaseInsensitiveContains(query) ||
                transaction.category.localizedCaseInsensitiveContains(query) ||
                (transaction.bank ?? "")
                    .localizedCaseInsensitiveContains(query) ||
                (transaction.note ?? "")
                    .localizedCaseInsensitiveContains(query)

            return matchesFilter && matchesSearch
        }
    }

    var body: some View {

        NavigationStack {

            VStack(spacing: 12) {

                Picker("Filter", selection: $filter) {

                    Text("All").tag("All")
                    Text("Expenses").tag("Expenses")
                    Text("Income").tag("Income")
                    Text("Review").tag("Review")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if filteredTransactions.isEmpty {

                    ContentUnavailableView(
                        "No transactions found",
                        systemImage: "magnifyingglass",
                        description: Text("Try changing your filters or search.")
                    )

                } else {

                    List {

                        ForEach(
                            filteredTransactions,
                            id: \.id
                        ) { transaction in

                            Button {

                                selectedTransaction = transaction
                                showEditor = true

                            } label: {

                                GhafTransactionRow(
                                    transaction: transaction,
                                    theme: theme
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(theme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(theme.background)
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                prompt: "Merchant, category or bank"
            )
            .sheet(isPresented: $showEditor) {

                if let transaction = selectedTransaction {

                    GhafTransactionEditor(
                        transaction: transaction,
                        categories: settings.categories
                    )
                }
            }
        }
    }
}

// MARK: - Transaction Editor

struct GhafTransactionEditor: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let transaction: GhafTransaction
    let categories: [String]

    @State private var amount: String
    @State private var merchant: String
    @State private var category: String
    @State private var direction: String
    @State private var note: String
    @State private var date: Date

    @State private var errorMessage = ""

    init(
        transaction: GhafTransaction,
        categories: [String]
    ) {

        self.transaction = transaction

        var availableCategories = categories

        if !availableCategories.contains(transaction.category) {
            availableCategories.append(transaction.category)
        }

        self.categories = availableCategories

        _amount = State(
            initialValue: GhafFormat.decimal(transaction.amount)
        )

        _merchant = State(
            initialValue: transaction.merchant ?? ""
        )

        _category = State(
            initialValue: transaction.category
        )

        _direction = State(
            initialValue: transaction.direction
        )

        _note = State(
            initialValue: transaction.note ?? ""
        )

        _date = State(
            initialValue: transaction.date
        )
    }

    var body: some View {

        NavigationStack {

            Form {

                Section("Details") {

                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)

                    TextField("Merchant", text: $merchant)

                    Picker("Direction", selection: $direction) {

                        Text("Expense").tag("debit")
                        Text("Income").tag("credit")
                    }

                    Picker("Category", selection: $category) {

                        ForEach(categories, id: \.self) {
                            Text($0).tag($0)
                        }
                    }

                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Additional information") {

                    TextField("Note", text: $note)
                }

                if !errorMessage.isEmpty {

                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit transaction")
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

        transaction.amount = value
        transaction.merchant = merchant.isEmpty ? nil : merchant
        transaction.category = category
        transaction.direction = direction
        transaction.note = note
        transaction.date = date

        transaction.needsReview = false

        if let merchantName = transaction.merchant,
           !merchantName.isEmpty {

            do {

                try MerchantCategorizer.learn(
                    merchant: merchantName,
                    category: category,
                    context: modelContext
                )

            } catch {

                errorMessage = "Could not save merchant rule."
                return
            }
        }

        do {

            try modelContext.save()
            dismiss()

        } catch {

            errorMessage = "Could not save changes."
        }
    }
}
