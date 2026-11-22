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
