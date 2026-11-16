import SwiftUI

/// Each city theme's skyline, drawn as one silhouette: Qasr Al Hosn and the Grand Mosque for Abu Dhabi,
/// Burj Khalifa and Burj Al Arab for Dubai, and so on. It sits faintly behind every screen and fills the
/// theme tiles, so a theme is a place, not only a colour.
struct GhafCitySkyline: Shape {
    let city: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        func box(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat) {
            path.addRect(CGRect(x: rect.minX + x0 * w, y: rect.minY + top * h, width: (x1 - x0) * w, height: (1 - top) * h))
        }
        func dome(_ cx: CGFloat, _ r: CGFloat, _ base: CGFloat) {
            path.addEllipse(in: CGRect(x: rect.minX + (cx - r) * w, y: rect.minY + base * h - r * w, width: 2 * r * w, height: 2 * r * w))
            box(cx - r, cx + r, base)
        }
        func minaret(_ x: CGFloat, _ top: CGFloat) {
            box(x - 0.006, x + 0.006, top)
            path.addEllipse(in: CGRect(x: rect.minX + (x - 0.009) * w, y: rect.minY + top * h - 0.02 * w, width: 0.018 * w, height: 0.03 * w))
        }
        func crenels(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat, count: Int) {
            let step = (x1 - x0) / CGFloat(count * 2 - 1)
            for k in 0..<count { box(x0 + CGFloat(k * 2) * step, x0 + CGFloat(k * 2 + 1) * step, top - 0.06) }
        }
        func poly(_ points: [(CGFloat, CGFloat)]) {
            path.move(to: p(points[0].0, points[0].1))
            for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
            path.closeSubpath()
        }
        func palm(_ x: CGFloat, _ top: CGFloat) {
            box(x - 0.004, x + 0.004, top)
            for k in 0..<5 {
                let angle = Double(k) / 4 * .pi
                let tip = p(x + CGFloat(cos(angle)) * 0.045, top - CGFloat(sin(angle)) * 0.12 + 0.05)
                path.move(to: p(x, top)); path.addQuadCurve(to: tip, control: p(x + CGFloat(cos(angle)) * 0.02, top - 0.12))
                path.addLine(to: p(x + CGFloat(cos(angle)) * 0.04, top - CGFloat(sin(angle)) * 0.1 + 0.06)); path.closeSubpath()
            }
        }
        func mountains(_ peaks: [(CGFloat, CGFloat)]) {
            var points: [(CGFloat, CGFloat)] = [(0, 1)]
            points += peaks
            points.append((1, 1))
            poly(points)
        }

        switch city {
        case "Abu Dhabi":
            // Qasr Al Hosn: two towers and a wall; the Grand Mosque: domes and four minarets.
            box(0.06, 0.13, 0.42); crenels(0.06, 0.13, 0.42, count: 3)
            box(0.13, 0.30, 0.62); crenels(0.13, 0.30, 0.62, count: 5)
            box(0.30, 0.36, 0.36); crenels(0.30, 0.36, 0.36, count: 2)
            dome(0.66, 0.07, 0.62); dome(0.57, 0.035, 0.66); dome(0.75, 0.035, 0.66)
            box(0.52, 0.80, 0.66)
            for x in [0.49, 0.53, 0.79, 0.83] as [CGFloat] { minaret(x, 0.22) }
            box(0.0, 1.0, 0.96)
        case "Dubai":
            // Burj Khalifa's stepped spire, Burj Al Arab's sail, and towers between.
            poly([(0.20, 1), (0.20, 0.55), (0.215, 0.55), (0.215, 0.32), (0.228, 0.32), (0.228, 0.14), (0.236, 0.14),
                  (0.24, 0.0), (0.244, 0.14), (0.252, 0.14), (0.252, 0.32), (0.265, 0.32), (0.265, 0.55), (0.28, 0.55), (0.28, 1)])
            box(0.06, 0.12, 0.58); box(0.13, 0.18, 0.46); box(0.31, 0.37, 0.50); box(0.39, 0.44, 0.62)
            box(0.47, 0.53, 0.40); box(0.55, 0.60, 0.56)
            path.move(to: p(0.72, 1)); path.addLine(to: p(0.72, 0.30))
            path.addQuadCurve(to: p(0.86, 1), control: p(0.86, 0.45)); path.closeSubpath()
            box(0.715, 0.725, 0.24)
            box(0.90, 0.96, 0.64)
            box(0.0, 1.0, 0.96)
        case "Sharjah":
            // Al Noor Mosque's domes and minarets over a row of arches.
            dome(0.30, 0.08, 0.60); dome(0.19, 0.04, 0.68); dome(0.41, 0.04, 0.68)
            box(0.14, 0.46, 0.68); minaret(0.12, 0.22); minaret(0.48, 0.22)
            for k in 0..<6 {
                let x = 0.56 + CGFloat(k) * 0.07
                box(x, x + 0.05, 0.72); path.addEllipse(in: CGRect(x: rect.minX + x * w, y: rect.minY + 0.72 * h - 0.025 * w, width: 0.05 * w, height: 0.05 * w))
            }
            box(0.0, 1.0, 0.96)
        case "Ajman":
            // Mangrove canopies on the water and a dhow.
            for (x, r) in [(0.08, 0.06), (0.17, 0.08), (0.27, 0.055), (0.62, 0.07), (0.72, 0.09), (0.84, 0.06)] as [(CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(x: rect.minX + (x - r) * w, y: rect.minY + 0.86 * h - r * 1.4 * w, width: 2 * r * w, height: r * 1.6 * w))
            }
            poly([(0.38, 0.86), (0.54, 0.86), (0.51, 0.93), (0.41, 0.93)])
            poly([(0.45, 0.85), (0.45, 0.40), (0.53, 0.80)])
            box(0.0, 1.0, 0.94)
        case "Umm Al Quwain":
            // The old fort's round tower and the lagoon's low islands.
            box(0.14, 0.24, 0.40); crenels(0.14, 0.24, 0.40, count: 3)
            box(0.24, 0.40, 0.62); crenels(0.24, 0.40, 0.62, count: 5)
            for (x, r) in [(0.60, 0.10), (0.80, 0.07), (0.94, 0.05)] as [(CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(x: rect.minX + (x - r) * w, y: rect.minY + 0.90 * h - 0.04 * w, width: 2 * r * w, height: 0.08 * w))
            }
            box(0.0, 1.0, 0.95)
        case "Ras Al Khaimah":
            // Jebel Jais and its ridges under a setting sun.
            path.addEllipse(in: CGRect(x: rect.minX + 0.70 * w, y: rect.minY + 0.18 * h, width: 0.12 * w, height: 0.12 * w))
            mountains([(0.10, 0.62), (0.22, 0.40), (0.30, 0.52), (0.46, 0.10), (0.58, 0.44), (0.66, 0.36), (0.82, 0.70), (0.92, 0.58)])
        case "Fujairah":
            // The Hajar mountains, Fujairah fort and date palms.
            mountains([(0.12, 0.50), (0.28, 0.20), (0.40, 0.46), (0.52, 0.30), (0.70, 0.66)])
            box(0.62, 0.72, 0.58); crenels(0.62, 0.72, 0.58, count: 3)
            box(0.72, 0.76, 0.42); crenels(0.72, 0.76, 0.42, count: 2)
            palm(0.84, 0.52); palm(0.92, 0.60); palm(0.08, 0.70)
            box(0.0, 1.0, 0.96)
        default:
            break
        }
        return path
    }
}

/// The skyline faded into the top of a screen's background. Hidden for Graphite, which has no city.
struct GhafCityBackdrop: View {
    let theme: GhafTheme

    var body: some View {
        GhafCitySkyline(city: theme.name)
            .fill(LinearGradient(colors: [theme.accent, theme.glow], startPoint: .top, endPoint: .bottom))
            .opacity(theme.isDark ? 0.10 : 0.075)
            .frame(height: 150)
            .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .center, endPoint: .bottom))
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 30)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        ForEach(GhafTheme.themeNames, id: \.self) { name in
            GhafCitySkyline(city: name).fill(.brown).frame(height: 70)
        }
    }
    .padding()
}
