import SwiftUI

struct GhafGlassSurface: ViewModifier {
    let theme: GhafTheme
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(theme.surface.opacity(0.74)))
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.38),
                            theme.outline.opacity(0.60),
                            .white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.055), radius: 15, x: 0, y: 7)
    }
}

extension View {
    func ghafGlass(theme: GhafTheme, radius: CGFloat = 22) -> some View {
        modifier(GhafGlassSurface(theme: theme, radius: radius))
    }
}

struct GhafGlassButtonStyle: ButtonStyle {
    let theme: GhafTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("IBMPlexSans-Regular", size: 16).weight(.semibold))
            .foregroundStyle(theme.accentContrast)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .padding(.horizontal, 18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.accent.opacity(configuration.isPressed ? 0.92 : 0.82))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.30), lineWidth: 1)
            }
            .shadow(color: theme.accent.opacity(0.15), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhafTreeMark: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Ellipse()
                    .fill(color)
                    .frame(width: side * 0.66, height: side * 0.27)
                    .offset(y: -side * 0.17)
                Circle()
                    .fill(color)
                    .frame(width: side * 0.39, height: side * 0.39)
                    .offset(x: -side * 0.20, y: -side * 0.19)
                Circle()
                    .fill(color)
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
