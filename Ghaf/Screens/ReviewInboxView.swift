import SwiftUI
import SwiftData

struct GhafReviewInboxView: View {

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

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

    private var reviewTransactions: [GhafTransaction] {
        transactions.filter { $0.needsReview }
    }

    var body: some View {
        NavigationStack {
            reviewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.ignoresSafeArea())
                .navigationTitle("Needs Review")
                .navigationBarTitleDisplayMode(.large)
                .sheet(isPresented: $showEditor) {
                    transactionEditorSheet
                }
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if reviewTransactions.isEmpty {
            emptyState
        } else {
            reviewList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(theme.comfortable)

            Text("You're all caught up.")
                .font(GhafTypeScale.title)
                .foregroundStyle(theme.primaryText)

            Text("There are no transactions waiting for review.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewList: some View {
        List {
            ForEach(reviewTransactions, id: \.id) { transaction in
                reviewRow(transaction)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func reviewRow(_ transaction: GhafTransaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GhafTransactionRow(
                transaction: transaction,
                theme: theme,
                languageCode: settings.languageCode
            )

            HStack(spacing: 10) {
                Button("Edit") {
                    selectedTransaction = transaction
                    showEditor = true
                }
                .buttonStyle(.bordered)

                Button("Accept") {
                    transaction.needsReview = false
                    try? modelContext.save()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
        .padding(14)
        .ghafGlass(theme: theme, radius: 20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var transactionEditorSheet: some View {
        if let transaction = selectedTransaction {
            GhafTransactionEditor(
                transaction: transaction,
                categories: settings.categories
            )
        }
    }
}
