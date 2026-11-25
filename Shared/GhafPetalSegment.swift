import SwiftUI

/// The rounded budget-petal segment shared by the Budget screen and Ghaf AI charts.
struct GhafPetalSegment: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2
        func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle * .pi / 180) * radius * r,
                    y: center.y + sin(angle * .pi / 180) * radius * r)
        }
        let outerRadius = radius * outer, innerRadius = radius * inner
        let petalWidth = outerRadius * CGFloat((end - start) * .pi / 180)
        let corner = min(14, petalWidth * 0.25, (outerRadius - innerRadius) / 2)
        let outerInset = min((end - start) * 0.22, Double(atan(corner / max(outerRadius - corner, 1))) * 180 / .pi)
        let innerInset = min((end - start) * 0.22, Double(atan(corner / max(innerRadius + corner, 1))) * 180 / .pi)
        func arcControl(_ from: Double, _ to: Double, _ r: CGFloat) -> CGPoint {
            let middle = (from + to) / 2
            return point(middle, r / CGFloat(cos((to - from) * .pi / 360)))
        }
        var path = Path()
        path.move(to: point(start, outer - corner / radius))
        path.addQuadCurve(to: point(start + outerInset, outer), control: point(start, outer))
        path.addQuadCurve(to: point(end - outerInset, outer), control: arcControl(start + outerInset, end - outerInset, outer))
        path.addQuadCurve(to: point(end, outer - corner / radius), control: point(end, outer))
        path.addLine(to: point(end, inner + corner / radius))
        path.addQuadCurve(to: point(end - innerInset, inner), control: point(end, inner))
        path.addQuadCurve(to: point(start + innerInset, inner), control: arcControl(end - innerInset, start + innerInset, inner))
        path.addQuadCurve(to: point(start, inner + corner / radius), control: point(start, inner))
        path.addLine(to: point(start, outer - corner / radius))
        path.closeSubpath()
        return path
    }
}
