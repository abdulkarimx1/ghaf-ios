import SwiftUI

extension View {
    /// Gives compact custom sheets a single clipped surface and keeps their content clear of the home indicator.
    func ghafSheetFrame(theme: GhafTheme, radius: CGFloat = 32) -> some View {
        self
            .safeAreaPadding(.bottom, 12)
            .background(theme.background.ignoresSafeArea())
            .presentationBackground { theme.background.ignoresSafeArea() }
            .presentationCornerRadius(radius)
    }
}

/// Owner 1.31 bottom cards: sized to their content (no empty white space), grabber + ✕, radius 40.
/// Style "floating" keeps the system glass card; "edge" is the same card in the solid theme colour.
/// iOS 26+ always floats partial-height sheets with side margins, so a true edge-to-edge card would need a custom presenter.
/// The A/B switch lives in Appearance until the owner picks one. shortcut: the scrim and push-back are the system's own, not the 34 % from the prototype.
struct GhafBottomCard: ViewModifier {
    static let styleKey = "ghaf.bottomCardStyle"
    let theme: GhafTheme
    let languageCode: String
    @AppStorage(styleKey) private var style = "floating"
    @State private var height: CGFloat = 320
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .padding(.top, 22)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(theme.primaryText.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.ghafPress)
                .padding(8)
                .accessibilityLabel(languageCode == "ar" ? "إغلاق" : "Close")
            }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(40)
            .modifier(Background(theme: theme, floating: style == "floating"))
    }

    private struct Background: ViewModifier {
        let theme: GhafTheme
        let floating: Bool
        func body(content: Content) -> some View {
            if floating, #available(iOS 26, *) {
                content // the system's floating glass card
            } else {
                content.presentationBackground { theme.background.ignoresSafeArea() }
            }
        }
    }
}

extension View {
    func ghafBottomCard(theme: GhafTheme, languageCode: String) -> some View {
        modifier(GhafBottomCard(theme: theme, languageCode: languageCode))
    }
}
