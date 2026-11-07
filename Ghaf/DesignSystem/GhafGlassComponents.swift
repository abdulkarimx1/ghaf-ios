import SwiftUI

struct GhafGlassSurface: ViewModifier {
    let theme: GhafTheme
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(theme.accent.opacity(0.055)))
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.30), theme.outline.opacity(0.48), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
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
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.accent.opacity(configuration.isPressed ? 0.20 : 0.12))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: theme.accent.opacity(0.12), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct GhafTreeMark: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(color.opacity(0.10)))
                ZStack {
                    Ellipse().fill(color)
                        .frame(width: side * 0.54, height: side * 0.27)
                        .offset(y: -side * 0.14)
                    Circle().fill(color)
                        .frame(width: side * 0.34, height: side * 0.34)
                        .offset(x: -side * 0.19, y: -side * 0.18)
                    Circle().fill(color)
                        .frame(width: side * 0.34, height: side * 0.34)
                        .offset(x: side * 0.19, y: -side * 0.18)
                    RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                        .fill(color)
                        .frame(width: side * 0.10, height: side * 0.34)
                        .offset(y: side * 0.22)
                }
                Circle().stroke(.white.opacity(0.28), lineWidth: 1)
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
        case "Groceries": return "basket"
        case "Dining": return "fork.knife"
        case "Transport": return "car"
        case "Fuel": return "fuelpump"
        case "Bills & Utilities": return "bolt"
        case "Shopping": return "bag"
        case "Health": return "cross.case"
        case "Entertainment": return "play.rectangle"
        case "Travel": return "airplane"
        case "Salary": return "banknote"
        case "Transfers": return "arrow.left.arrow.right"
        default: return "creditcard"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
    }
}
