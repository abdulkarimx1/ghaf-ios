import SwiftUI

struct GhafMerchantSummary: Identifiable {
    let name: String
    let total: Decimal
    let count: Int
    let category: String

    var id: String { name }
}

struct GhafTopMerchantsView: View {
    let merchants: [GhafMerchantSummary]
    let currency: String
    let languageCode: String
    let theme: GhafTheme

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                GhafScreenTitle(title: ar ? "أكثر المتاجر" : "Top merchants", subtitle: nil,
                                languageCode: languageCode, theme: theme)
                if merchants.isEmpty {
                    Text(ar ? "لا توجد متاجر في هذه الفترة." : "No merchants in this period.")
                        .font(GhafTypography.body(14, languageCode: languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(spacing: 0) {
                        ForEach(merchants) { merchant in
                            GhafMerchantRankingRow(merchant: merchant, currency: currency,
                                                   languageCode: languageCode, theme: theme,
                                                   maximum: merchants.first?.total ?? 1)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ghafStatsCard(theme: theme)
                }
            }
            .ghafScreenPadding()
            .padding(.top, 12)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ghafReportsTabBarMinimize()
        .ghafBackground(theme: theme)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }
}

struct GhafMerchantRankingRow: View {
    let merchant: GhafMerchantSummary
    let currency: String
    let languageCode: String
    let theme: GhafTheme
    let maximum: Decimal

    private var ar: Bool { languageCode == "ar" }
    private var ratio: CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: merchant.total / maximum).doubleValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            GhafCategoryIcon(category: merchant.category, tint: theme.accent, theme: theme)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(merchant.name).font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.primaryText).lineLimit(1)
                    Spacer(minLength: 6)
                    GhafMoneyLabel(amount: merchant.total, currency: currency, languageCode: languageCode, size: 14)
                        .foregroundStyle(theme.primaryText).lineLimit(1).minimumScaleFactor(0.8)
                }
                GeometryReader { proxy in
                    Capsule().fill(theme.accent.opacity(0.85)).frame(width: max(6, proxy.size.width * ratio))
                }
                .frame(height: 5)
                Text(ar ? "\(merchant.count) عملية" : "\(merchant.count) purchases")
                    .font(GhafTypography.body(11, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
