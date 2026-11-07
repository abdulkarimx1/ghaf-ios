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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    if reviewTransactions.isEmpty {
                        emptyState
                    } else {
                        reviewList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditor) {
                transactionEditorSheet
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MERCHANT LEARNING")
                .font(GhafTypography.body(10, languageCode: settings.languageCode, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(theme.secondaryText)

            Text(settings.languageCode == "ar" ? "تحتاج مراجعتك" : "Needs review")
                .font(GhafTypography.display(31, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)

            Text(settings.languageCode == "ar"
                 ? "صحّح الفئة مرة واحدة ليتعلم غاف اختيارك."
                 : "Correct a category once and Ghaf learns your choice.")
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(theme.comfortable)

            Text(settings.languageCode == "ar" ? "كل شيء واضح." : "You're all caught up.")
                .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)

            Text(settings.languageCode == "ar"
                 ? "لا توجد عمليات تنتظر المراجعة."
                 : "There are no transactions waiting for review.")
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .ghafCard(theme: theme, radius: 20)
        .padding(.top, 6)
    }

    private var reviewList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(settings.languageCode == "ar" ? "عمليات غير مؤكدة" : "Unconfirmed activity")
                    .font(GhafTypography.heading(18, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(reviewTransactions.count)")
                    .font(GhafTypography.number(13, weight: .bold))
                    .foregroundStyle(theme.accentContrast)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.accent, in: Capsule())
            }

            ForEach(reviewTransactions, id: \.id) { transaction in
                reviewCard(transaction)
            }
        }
    }

    private func reviewCard(_ transaction: GhafTransaction) -> some View {
        VStack(spacing: 12) {
            GhafTransactionRow(
                transaction: transaction,
                theme: theme,
                languageCode: settings.languageCode
            )

            HStack(spacing: 9) {
                Button(settings.languageCode == "ar" ? "تعديل الفئة" : "Edit category") {
                    selectedTransaction = transaction
                    showEditor = true
                }
                .ghafProminentButton(theme: theme)

                Button {
                    transaction.needsReview = false
                    try? modelContext.save()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.credit)
                        .frame(width: 52, height: 52)
                        .background(theme.credit.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept category")
            }
        }
        .padding(15)
        .ghafCard(theme: theme, radius: 19)
    }

    @ViewBuilder
    private var transactionEditorSheet: some View {
        if let transaction = selectedTransaction {
            GhafTransactionEditor(
                transaction: transaction,
                categories: settings.categories,
                themeName: settings.themeName,
                appearanceMode: settings.appearanceMode,
                languageCode: settings.languageCode
            )
        }
    }
}
