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

/// Owner 1.31 bottom cards (owner picked Solid): sized to their content (no empty white space), grabber + ✕, radius 40.
struct GhafBottomCard: ViewModifier {
    let theme: GhafTheme
    let languageCode: String
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
            .presentationBackground { theme.background.ignoresSafeArea() }
    }
}

extension View {
    func ghafBottomCard(theme: GhafTheme, languageCode: String) -> some View {
        modifier(GhafBottomCard(theme: theme, languageCode: languageCode))
    }
}
