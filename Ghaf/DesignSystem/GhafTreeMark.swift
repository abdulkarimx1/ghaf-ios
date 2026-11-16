import SwiftUI

/// Ghaf AI's mark: a solid Ghaf tree (Prosopis cineraria, the UAE's national tree): a wide,
/// low canopy on a short trunk that forks just below it. Drawn as one filled silhouette.
struct GhafTreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func ellipse(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
            Path(ellipseIn: CGRect(origin: p(x0, y0), size: CGSize(width: (x1 - x0) * rect.width, height: (y1 - y0) * rect.height)))
        }

        // Canopy: a tall middle crown and two lower side crowns over a flat base.
        var canopy = ellipse(0.16, 0.06, 0.84, 0.46)
        canopy = canopy.union(ellipse(0.02, 0.20, 0.48, 0.56))
        canopy = canopy.union(ellipse(0.52, 0.20, 0.98, 0.56))
        canopy = canopy.union(Path(roundedRect: CGRect(origin: p(0.10, 0.30), size: CGSize(width: 0.80 * rect.width, height: 0.24 * rect.height)),
                                   cornerRadius: 0.10 * rect.width))

        // Trunk: wide at the ground, forking into two limbs that disappear into the canopy.
        var trunk = Path()
        trunk.move(to: p(0.36, 0.93))
        trunk.addQuadCurve(to: p(0.44, 0.70), control: p(0.43, 0.82))
        trunk.addLine(to: p(0.25, 0.50))
        trunk.addLine(to: p(0.40, 0.47))
        trunk.addLine(to: p(0.50, 0.60))
        trunk.addLine(to: p(0.60, 0.47))
        trunk.addLine(to: p(0.75, 0.50))
        trunk.addLine(to: p(0.56, 0.70))
        trunk.addQuadCurve(to: p(0.64, 0.93), control: p(0.57, 0.82))
        trunk.closeSubpath()

        let ground = Path(roundedRect: CGRect(origin: p(0.18, 0.90), size: CGSize(width: 0.64 * rect.width, height: 0.08 * rect.height)),
                          cornerRadius: 0.04 * rect.height)
        return canopy.union(trunk).union(ground)
    }
}

#Preview {
    GhafTreeShape()
        .fill(LinearGradient(colors: [.orange, .brown], startPoint: .top, endPoint: .bottom))
        .frame(width: 200, height: 200)
}
