import SwiftUI

private struct GhafCardSurface: ViewModifier {
    let theme: GhafTheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(theme.surface, in: shape)
            .overlay {
                shape.stroke(theme.outline.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 5)
    }
}

private struct GhafLiquidGlassSurface: ViewModifier {
    let theme: GhafTheme
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(theme.accent.opacity(0.12)).interactive(),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
        } else {
            content.modifier(GhafCardSurface(theme: theme, radius: radius))
        }
    }
}

extension View {
    func ghafCard(theme: GhafTheme, radius: CGFloat = 22) -> some View {
        modifier(GhafCardSurface(theme: theme, radius: radius))
    }

    func ghafLiquidGlass(theme: GhafTheme, radius: CGFloat = 22) -> some View {
        modifier(GhafLiquidGlassSurface(theme: theme, radius: radius))
    }

    @ViewBuilder
    func ghafProminentButton(
        theme: GhafTheme,
        languageCode: String = "en"
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold))
                .tint(theme.accent)
                .buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(GhafPrimaryButtonStyle(theme: theme))
        }
    }

    @ViewBuilder
    func ghafGlassButton(
        theme: GhafTheme,
        languageCode: String = "en"
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .tint(theme.accent)
                .buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).tint(theme.accent)
        }
    }
}

struct GhafTreeMark: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Ellipse().fill(color)
                    .frame(width: side * 0.66, height: side * 0.27)
                    .offset(y: -side * 0.17)
                Circle().fill(color)
                    .frame(width: side * 0.39, height: side * 0.39)
                    .offset(x: -side * 0.20, y: -side * 0.19)
                Circle().fill(color)
                    .frame(width: side * 0.39, height: side * 0.39)
                    .offset(x: side * 0.20, y: -side * 0.19)
                RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                    .fill(color)
                    .frame(width: side * 0.105, height: side * 0.42)
                    .offset(y: side * 0.23)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("Ghaf tree")
    }
}

struct GhafCategoryIcon: View {
    let category: String
    let tint: Color

    private var symbol: String {
        switch category {
        case "Groceries": "basket"
        case "Dining": "fork.knife"
        case "Transport": "car"
        case "Fuel": "fuelpump"
        case "Bills & Utilities": "bolt"
        case "Shopping": "bag"
        case "Health": "cross.case"
        case "Entertainment": "play.rectangle"
        case "Travel": "airplane"
        case "Salary": "banknote"
        case "Transfers": "arrow.left.arrow.right"
        default: "creditcard"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
