import SwiftUI

struct GhafConfirmCard: View {
    let title: String
    let message: String
    let keepTitle: String
    let discardTitle: String
    let theme: GhafTheme
    let languageCode: String
    let keep: () -> Void
    let discard: () -> Void

    // Owner #52: rises from the bottom like the streak card, no dimmed backdrop.
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture(perform: keep)
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
            .shadow(color: .black.opacity(0.18), radius: 24, y: -4)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
