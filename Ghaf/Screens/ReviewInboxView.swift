import SwiftUI
import SwiftData

struct GhafReviewInboxView: View {

    @Environment(\.colorScheme) private var systemColorScheme

    @Query(sort: \GhafTransaction.date, order: .reverse)
    private var transactions: [GhafTransaction]

    @Environment(\.modelContext) private var modelContext

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

        transactions.filter {
            $0.needsReview
        }
    }

    var body: some View {

        NavigationStack {

            Group {

                if reviewTransactions.isEmpty {

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

                } else {

                    List {

                        ForEach(
                            reviewTransactions,
                            id: \.id
                        ) { transaction in

                            VStack(alignment: .leading, spacing: 12) {

                                GhafTransactionRow(
                                    transaction: transaction,
                                    theme: theme
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
                            .padding(.vertical, 8)
                            .listRowBackground(theme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(theme.background)
            .navigationTitle("Needs Review")
            .navigationBarTitleDisplayMode(.large)
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
