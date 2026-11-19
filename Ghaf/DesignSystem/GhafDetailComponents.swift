import SwiftUI

/// Shared pieces for every detail page (transactions, subscriptions) so they read as one app:
/// a centred status mark, receipt-style rows, and the same bottom action bar.

/// Large status mark: a soft ring around a tinted circle with a symbol or company mark.
struct GhafStatusMark<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: 104, height: 104)
            Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
            content()
        }
        .accessibilityHidden(true)
    }
}

/// One label/value line of a receipt card.
struct GhafDetailRow<Value: View>: View {
    let label: String
    let theme: GhafTheme
    let languageCode: String
    /// Hairline under the row; off for the last row of a card.
    var divider = true
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(GhafTypography.body(14, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 12)
            value()
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .frame(minHeight: GhafMetrics.rowHeight)
        .overlay(alignment: .bottom) { if divider { Divider().overlay(theme.outline) } }
        .accessibilityElement(children: .combine)
    }
}

extension GhafDetailRow where Value == Text {
    init(label: String, text: String, theme: GhafTheme, languageCode: String, divider: Bool = true) {
        self.init(label: label, theme: theme, languageCode: languageCode, divider: divider) { Text(text) }
    }
}

/// Grouped rows on the app's card surface, separated by hairlines.
struct GhafDetailCard<Content: View>: View {
    let theme: GhafTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .ghafCard(theme: theme)
    }
}

/// Bottom bar used by every detail page: an optional round secondary action and one primary action.
struct GhafDetailActionBar: View {
    let theme: GhafTheme
    let languageCode: String
    var secondarySymbol: String? = nil
    var secondaryLabel: String = ""
    var secondaryAction: () -> Void = {}
    let primaryTitle: String
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let secondarySymbol {
                Button(action: secondaryAction) {
                    Image(systemName: secondarySymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 64, height: 56)
                        .ghafGlassShape(theme: theme, shape: Capsule(), fallback: theme.surface)
                }
                .buttonStyle(.ghafPress)
                .accessibilityLabel(secondaryLabel)
            }
            GhafPrimaryButton(title: primaryTitle, theme: theme, languageCode: languageCode, action: primaryAction)
        }
        .ghafScreenPadding()
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [theme.background.opacity(0), theme.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                theme.background
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
