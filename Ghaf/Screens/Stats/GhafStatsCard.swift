import SwiftUI

extension View {
    func ghafStatsCard(theme: GhafTheme, radius: CGFloat = GhafMetrics.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(theme.surface, in: shape)
            .overlay(shape.stroke(theme.outline.opacity(theme.isDark ? 0.75 : 0.45), lineWidth: 1))
    }
}
