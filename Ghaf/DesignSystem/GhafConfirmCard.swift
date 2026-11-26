import SwiftUI

struct GhafConfirmCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let message: String
    let keepTitle: String
    let discardTitle: String
    let theme: GhafTheme
    let languageCode: String
    let keep: () -> Void
    let discard: () -> Void

    // Owner #52 (2026-11-26): the backdrop is dimmed while the card rises from the bottom.
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(theme.isDark ? 0.5 : 0.3)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: keep)
                .accessibilityHidden(true)
                .transition(.opacity)
            VStack(spacing: 12) {
                Capsule().fill(theme.secondaryText.opacity(0.35)).frame(width: 36, height: 5).padding(.bottom, 6)
                Text(title).font(GhafTypography.heading(21, languageCode: languageCode)).foregroundStyle(theme.primaryText).multilineTextAlignment(.center)
                Text(message).font(GhafTypography.body(15, languageCode: languageCode)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                Button(keepTitle, action: keep).buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .primary))
                Button(discardTitle, action: discard).buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .destructive))
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 34)
            .frame(maxWidth: .infinity)
            .background(theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous))
            // Owner 2026-11-26: in dark mode a faint edge separates the card from the dimmed screen.
            .overlay {
                if theme.isDark {
                    UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: -4)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
