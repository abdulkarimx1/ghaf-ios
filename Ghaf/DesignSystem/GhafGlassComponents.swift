import SwiftUI

private struct GhafCardSurface: ViewModifier {
    let theme: GhafTheme
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let isDark = colorScheme == .dark
        content
            .background {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(theme.surface.opacity(isDark ? 0.48 : 0.24)))
            }
            .overlay {
                shape.stroke(.white.opacity(isDark ? 0.16 : 0.72), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                shape.stroke(theme.accent.opacity(isDark ? 0.20 : 0.22), lineWidth: 0.9)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(isDark ? 0.10 : 0.48), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
                .padding(1)
            }
            .shadow(color: .black.opacity(isDark ? 0.16 : 0.075), radius: 18, x: 0, y: 8)
    }
}

private struct GhafLiquidGlassSurface: ViewModifier {
    let theme: GhafTheme
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(theme.accent.opacity(0.09)),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
        } else {
            content.modifier(GhafCardSurface(theme: theme, radius: radius))
        }
    }
}

extension View {
    func ghafCard(theme: GhafTheme, radius: CGFloat = 22) -> some View {
        modifier(GhafLiquidGlassSurface(theme: theme, radius: radius))
    }

    func ghafBackground(theme: GhafTheme) -> some View {
        background {
            ZStack {
                theme.background.ignoresSafeArea()
                GhafCityBackdrop(theme: theme)
                    .ignoresSafeArea()
            }
        }
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


struct GhafCityBackdrop: View {
    let theme: GhafTheme

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                var drawing = Path()
                let w = size.width
                let h = size.height
                let origin = CGPoint(x: w * 0.68, y: h * 0.36)
                let scale = min(w, h) * 0.48

                switch theme.name {
                case "Dubai":
                    drawing.move(to: CGPoint(x: origin.x - scale * 0.40, y: origin.y + scale * 0.55))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.40, y: origin.y + scale * 0.12))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.22, y: origin.y + scale * 0.12))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.12, y: origin.y - scale * 0.32))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.03, y: origin.y - scale * 0.32))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.03, y: origin.y - scale * 0.84))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.09, y: origin.y - scale * 0.32))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.20, y: origin.y - scale * 0.32))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.20, y: origin.y + scale * 0.55))
                    drawing.move(to: CGPoint(x: origin.x + scale * 0.31, y: origin.y + scale * 0.55))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.31, y: origin.y - scale * 0.08))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.55, y: origin.y - scale * 0.08))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.55, y: origin.y + scale * 0.55))
                case "Sharjah":
                    for offset in [-0.48, -0.08, 0.30] {
                        let x = origin.x + scale * offset
                        drawing.addRect(CGRect(x: x, y: origin.y + scale * 0.02, width: scale * 0.25, height: scale * 0.50))
                        drawing.addRect(CGRect(x: x + scale * 0.06, y: origin.y - scale * 0.12, width: scale * 0.13, height: scale * 0.14))
                        drawing.move(to: CGPoint(x: x + scale * 0.12, y: origin.y - scale * 0.12))
                        drawing.addLine(to: CGPoint(x: x + scale * 0.12, y: origin.y - scale * 0.27))
                    }
                    drawing.move(to: CGPoint(x: origin.x - scale * 0.56, y: origin.y + scale * 0.52))
                    drawing.addQuadCurve(to: CGPoint(x: origin.x + scale * 0.64, y: origin.y + scale * 0.52), control: CGPoint(x: origin.x, y: origin.y + scale * 0.32))
                case "Ajman":
                    drawing.addRect(CGRect(x: origin.x + scale * 0.20, y: origin.y - scale * 0.42, width: scale * 0.12, height: scale * 0.88))
                    drawing.move(to: CGPoint(x: origin.x + scale * 0.16, y: origin.y - scale * 0.42))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.36, y: origin.y - scale * 0.42))
                    drawing.addEllipse(in: CGRect(x: origin.x + scale * 0.12, y: origin.y - scale * 0.58, width: scale * 0.28, height: scale * 0.18))
                    for row in 0..<3 {
                        let y = origin.y + scale * (0.18 + Double(row) * 0.13)
                        drawing.move(to: CGPoint(x: origin.x - scale * 0.58, y: y))
                        drawing.addQuadCurve(to: CGPoint(x: origin.x + scale * 0.60, y: y), control: CGPoint(x: origin.x, y: y - scale * 0.16))
                    }
                case "Umm Al Quwain":
                    drawing.move(to: CGPoint(x: origin.x - scale * 0.10, y: origin.y + scale * 0.48))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.05, y: origin.y - scale * 0.08))
                    for angle in [-1.0, -0.5, 0.25, 0.72, 1.15] {
                        let end = CGPoint(x: origin.x - scale * 0.05 + scale * 0.42 * cos(angle), y: origin.y - scale * 0.10 + scale * 0.32 * sin(angle))
                        drawing.move(to: CGPoint(x: origin.x - scale * 0.05, y: origin.y - scale * 0.08))
                        drawing.addLine(to: end)
                        drawing.addEllipse(in: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8))
                    }
                    for row in 0..<2 {
                        let y = origin.y + scale * (0.34 + Double(row) * 0.13)
                        drawing.move(to: CGPoint(x: origin.x - scale * 0.60, y: y))
                        drawing.addQuadCurve(to: CGPoint(x: origin.x + scale * 0.62, y: y), control: CGPoint(x: origin.x, y: y - scale * 0.13))
                    }
                case "Ras Al Khaimah", "Fujairah":
                    drawing.move(to: CGPoint(x: origin.x - scale * 0.70, y: origin.y + scale * 0.55))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.36, y: origin.y + scale * 0.14))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.21, y: origin.y + scale * 0.24))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.02, y: origin.y - scale * 0.34))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.21, y: origin.y + scale * 0.02))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.36, y: origin.y - scale * 0.06))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.70, y: origin.y + scale * 0.55))
                    if theme.name == "Fujairah" {
                        drawing.addRect(CGRect(x: origin.x - scale * 0.08, y: origin.y + scale * 0.24, width: scale * 0.20, height: scale * 0.24))
                        drawing.addRect(CGRect(x: origin.x - scale * 0.03, y: origin.y + scale * 0.12, width: scale * 0.10, height: scale * 0.12))
                    }
                default: // Abu Dhabi: waterfront dome and colonnade.
                    drawing.addEllipse(in: CGRect(x: origin.x - scale * 0.23, y: origin.y - scale * 0.26, width: scale * 0.46, height: scale * 0.42))
                    drawing.move(to: CGPoint(x: origin.x - scale * 0.23, y: origin.y - scale * 0.05))
                    drawing.addLine(to: CGPoint(x: origin.x - scale * 0.23, y: origin.y + scale * 0.50))
                    drawing.move(to: CGPoint(x: origin.x + scale * 0.23, y: origin.y - scale * 0.05))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.23, y: origin.y + scale * 0.50))
                    drawing.addLine(to: CGPoint(x: origin.x + scale * 0.56, y: origin.y + scale * 0.50))
                    for index in 0..<4 {
                        let x = origin.x - scale * 0.15 + Double(index) * scale * 0.10
                        drawing.addArc(center: CGPoint(x: x, y: origin.y + scale * 0.13), radius: scale * 0.07, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    }
                }

                context.stroke(drawing, with: .color(theme.accent.opacity(0.24)), lineWidth: 1.65)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
