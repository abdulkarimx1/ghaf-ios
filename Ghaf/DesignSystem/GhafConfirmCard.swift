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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.background.opacity(0.55).ignoresSafeArea().onTapGesture(perform: keep)
                VStack(spacing: 12) {
                    Text(title).font(GhafTypography.heading(21, languageCode: languageCode)).foregroundStyle(theme.primaryText).multilineTextAlignment(.center)
                    Text(message).font(GhafTypography.body(15, languageCode: languageCode)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
                    Button(keepTitle, action: keep).buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .primary))
                    Button(discardTitle, action: discard).buttonStyle(GhafCapsuleButtonStyle(theme: theme, languageCode: languageCode, role: .destructive))
                }
                .padding(24).frame(width: max(0, proxy.size.width - 48))
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.outline, lineWidth: 1))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
