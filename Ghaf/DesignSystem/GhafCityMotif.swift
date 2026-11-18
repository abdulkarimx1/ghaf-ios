import SwiftUI

/// Each city theme drawn as a small three-layer scene of its own landmarks: a faint far layer, the
/// signature landmark, and a near layer. Original drawings, made from merged shapes so overlaps never
/// leave gaps. Used in the theme picker, on Home and faintly behind every screen.
struct GhafCitySkyline: Shape {
    enum Layer: CaseIterable { case back, mid, front }
    let city: String
    var layer: Layer = .mid
    /// Only this layer's palms and mangroves (they sway in the backdrop); otherwise everything else.
    var foliage = false

    // SwiftUI may draw shapes off the main thread, so the cache is guarded by a lock, not an actor.
    private static let cache = GhafPathCache()

    func path(in rect: CGRect) -> Path {
        let key = "\(city)-\(layer)-\(foliage)-\(Int(rect.width))x\(Int(rect.height))"
        if let cached = Self.cache[key] {
            return cached.offsetBy(dx: rect.minX, dy: rect.minY)
        }
        var scene = Scene(size: rect.size)
        switch (city, layer) {
        case ("Abu Dhabi", .back): scene.abuDhabiBack()
        case ("Abu Dhabi", .mid): scene.abuDhabiMid()
        case ("Abu Dhabi", .front): scene.abuDhabiFront()
        case ("Dubai", .back): scene.dubaiBack()
        case ("Dubai", .mid): scene.dubaiMid()
        case ("Dubai", .front): scene.dubaiFront()
        case ("Sharjah", .back): scene.sharjahBack()
        case ("Sharjah", .mid): scene.sharjahMid()
        case ("Sharjah", .front): scene.sharjahFront()
        case ("Ajman", .back): scene.ajmanBack()
        case ("Ajman", .mid): scene.ajmanMid()
        case ("Ajman", .front): scene.ajmanFront()
        case ("Umm Al Quwain", .back): scene.uaqBack()
        case ("Umm Al Quwain", .mid): scene.uaqMid()
        case ("Umm Al Quwain", .front): scene.uaqFront()
        case ("Ras Al Khaimah", .back): scene.rakBack()
        case ("Ras Al Khaimah", .mid): scene.rakMid()
        case ("Ras Al Khaimah", .front): scene.rakFront()
        case ("Fujairah", .back): scene.fujairahBack()
        case ("Fujairah", .mid): scene.fujairahMid()
        case ("Fujairah", .front): scene.fujairahFront()
        default: break
        }
        let path = foliage ? scene.foliage : scene.path
        Self.cache[key] = path
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A small thread-safe store for drawn paths (iOS 17 has no Mutex).
private final class GhafPathCache: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String: Path] = [:]
    subscript(key: String) -> Path? {
        get { lock.withLock { paths[key] } }
        set { lock.withLock { paths[key] = newValue } }
    }
}

/// Drawing helpers in a unit space: x 0…1 across, y 0 (top) … 1 (ground). Round things use the
/// height for both radii so circles stay round at any width.
private struct Scene {
    let size: CGSize
    var path = Path()
    /// Palms and mangroves, kept apart so they can move without bending buildings.
    var foliage = Path()
    private var drawingFoliage = false

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }

    mutating func add(_ piece: Path) {
        if drawingFoliage { foliage = foliage.isEmpty ? piece : foliage.union(piece) }
        else { path = path.isEmpty ? piece : path.union(piece) }
    }
    mutating func cut(_ piece: Path) { path = path.subtracting(piece) }

    func rect(_ x0: CGFloat, _ x1: CGFloat, top: CGFloat, bottom: CGFloat = 1) -> Path {
        Path(CGRect(x: x0 * w, y: top * h, width: (x1 - x0) * w, height: (bottom - top) * h))
    }
    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx * w - r * h, y: (cy - r) * h, width: 2 * r * h, height: 2 * r * h))
    }
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, rx: CGFloat, ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: (cx - rx) * w, y: (cy - ry) * h, width: 2 * rx * w, height: 2 * ry * h))
    }
    func poly(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.move(to: p(points[0].0, points[0].1))
        for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
        path.closeSubpath()
        return path
    }
    func line(_ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), width: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(from.0, from.1)); path.addLine(to: p(to.0, to.1))
        return path.strokedPath(StrokeStyle(lineWidth: width * h, lineCap: .round))
    }
    func ring(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, width: CGFloat) -> Path {
        circle(cx, cy, r).strokedPath(StrokeStyle(lineWidth: width * h))
    }

    // MARK: Shared pieces

    /// A dome on a drum, with a finial: centre x, base y, radius (height units).
    mutating func dome(_ cx: CGFloat, base: CGFloat, r: CGFloat, finial: Bool = true) {
        add(circle(cx, base, r))
        add(rect(cx - r * h / w, cx + r * h / w, top: base, bottom: min(base + r * 0.5, 1)))
        if finial { add(line((cx, base - r), (cx, base - r - 0.06), width: 0.012)) }
    }
    /// A slim minaret with two balconies and a pointed cap.
    mutating func minaret(_ x: CGFloat, top: CGFloat, width: CGFloat = 0.012) {
        add(rect(x - width / 2, x + width / 2, top: top))
        for y in [top + 0.12, top + 0.32] { add(rect(x - width, x + width, top: y, bottom: y + 0.025)) }
        add(poly([(x - width * 0.7, top), (x, top - 0.07), (x + width * 0.7, top)]))
    }
    /// A tower with crenellations on top.
    mutating func fortTower(_ x0: CGFloat, _ x1: CGFloat, top: CGFloat, merlons: Int) {
        add(rect(x0, x1, top: top))
        let step = (x1 - x0) / CGFloat(merlons * 2 - 1)
        for k in 0..<merlons { add(rect(x0 + CGFloat(2 * k) * step, x0 + CGFloat(2 * k + 1) * step, top: top - 0.05, bottom: top)) }
    }
    mutating func palm(_ x: CGFloat, top: CGFloat, size s: CGFloat = 1) {
        drawingFoliage = true; defer { drawingFoliage = false }
        var trunk = Path()
        trunk.move(to: p(x - 0.004 * s, 1)); trunk.addQuadCurve(to: p(x + 0.004 * s, top), control: p(x + 0.012 * s, (1 + top) / 2))
        add(trunk.strokedPath(StrokeStyle(lineWidth: 0.018 * h * s, lineCap: .round)))
        for (dx, dy) in [(-0.05, 0.05), (-0.035, -0.05), (0, -0.07), (0.035, -0.05), (0.05, 0.05)] as [(CGFloat, CGFloat)] {
            var frond = Path()
            frond.move(to: p(x, top))
            frond.addQuadCurve(to: p(x + dx * s, top + (dy + 0.04) * s), control: p(x + dx * 0.6 * s, top + (dy - 0.06) * s))
            add(frond.strokedPath(StrokeStyle(lineWidth: 0.022 * h * s, lineCap: .round)))
        }
    }
    mutating func water(from x0: CGFloat = 0, to x1: CGFloat = 1) {
        add(rect(x0, x1, top: 0.95))
        for (k, y) in [0.86, 0.91].enumerated() {
            var wave = Path()
            let start = x0 + 0.03 + CGFloat(k) * 0.05
            wave.move(to: p(start, y))
            var x = start
            while x < x1 - 0.06 {
                wave.addQuadCurve(to: p(x + 0.06, y), control: p(x + 0.03, y - 0.03)); x += 0.09
                wave.move(to: p(x, y))
            }
            add(wave.strokedPath(StrokeStyle(lineWidth: 0.012 * h, lineCap: .round)))
        }
    }
    mutating func ground() { add(rect(0, 1, top: 0.96)) }
    mutating func mangrove(_ cx: CGFloat, _ r: CGFloat) {
        drawingFoliage = true; defer { drawingFoliage = false }
        // Rounded canopy clumps over stilt roots.
        add(ellipse(cx, 0.80 - r * 1.1, rx: r * 0.32, ry: r * 1.0))
        add(ellipse(cx - r * 0.28, 0.82 - r * 0.7, rx: r * 0.26, ry: r * 0.8))
        add(ellipse(cx + r * 0.28, 0.82 - r * 0.6, rx: r * 0.25, ry: r * 0.75))
        for dx in [-0.02, -0.007, 0.007, 0.02] as [CGFloat] { add(line((cx + dx * 0.5, 0.80), (cx + dx * 1.6, 0.96), width: 0.01)) }
    }
    mutating func mountains(_ peaks: [(CGFloat, CGFloat)]) {
        add(poly([(0, 1)] + peaks + [(1, 1)]))
    }

    // MARK: Abu Dhabi — Etihad Towers, Sheikh Zayed Grand Mosque, Qasr Al Hosn

    mutating func abuDhabiBack() {
        for (x, top) in [(0.70, 0.20), (0.76, 0.10), (0.82, 0.16), (0.88, 0.26), (0.94, 0.32)] as [(CGFloat, CGFloat)] {
            add(Path(roundedRect: CGRect(x: (x - 0.022) * w, y: top * h, width: 0.044 * w, height: (1 - top) * h),
                     cornerRadius: 0.022 * w))
        }
        mountains([(0.0, 0.84), (0.25, 0.76), (0.5, 0.86), (0.7, 0.8), (1, 0.86)])
    }
    mutating func abuDhabiMid() {
        add(rect(0.08, 0.50, top: 0.64))
        dome(0.29, base: 0.58, r: 0.17)
        dome(0.17, base: 0.64, r: 0.08); dome(0.41, base: 0.64, r: 0.08)
        dome(0.11, base: 0.66, r: 0.05, finial: false); dome(0.47, base: 0.66, r: 0.05, finial: false)
        for x in [0.05, 0.53] as [CGFloat] { minaret(x, top: 0.14) }
        ground()
    }
    mutating func abuDhabiFront() {
        // Qasr Al Hosn: round tower, square tower and the wall with its gate.
        add(rect(0.60, 0.78, top: 0.62)); fortTower(0.56, 0.62, top: 0.40, merlons: 3); fortTower(0.76, 0.81, top: 0.48, merlons: 3)
        add(circle(0.59, 0.40, 0.02))
        cut(rect(0.665, 0.705, top: 0.76, bottom: 0.96))
        cut(Path(ellipseIn: CGRect(x: 0.665 * w, y: 0.72 * h, width: 0.04 * w, height: 0.08 * h)))
        palm(0.88, top: 0.52); palm(0.95, top: 0.6, size: 0.8)
        ground()
    }

    // MARK: Dubai — skyline, Burj Khalifa, Museum of the Future, Dubai Frame, Burj Al Arab

    mutating func dubaiBack() {
        for (x0, x1, top) in [(0.02, 0.07, 0.50), (0.08, 0.12, 0.36), (0.13, 0.18, 0.56), (0.37, 0.41, 0.42), (0.42, 0.47, 0.30),
                              (0.48, 0.52, 0.50)] as [(CGFloat, CGFloat, CGFloat)] { add(rect(x0, x1, top: top)) }
        // Dubai Frame.
        add(rect(0.55, 0.57, top: 0.30)); add(rect(0.63, 0.65, top: 0.30)); add(rect(0.55, 0.65, top: 0.30, bottom: 0.35))
    }
    mutating func dubaiMid() {
        // Burj Khalifa: stacked setbacks rising to the spire.
        for (half, top) in [(0.045, 0.62), (0.035, 0.46), (0.026, 0.32), (0.018, 0.20), (0.011, 0.10)] as [(CGFloat, CGFloat)] {
            add(rect(0.27 - half, 0.27 + half, top: top))
        }
        add(poly([(0.265, 0.10), (0.27, -0.02), (0.275, 0.10)]))
        // Museum of the Future: a torus on a low mound.
        add(ellipse(0.78, 0.62, rx: 0.075, ry: 0.22).subtracting(ellipse(0.785, 0.60, rx: 0.038, ry: 0.13)))
        add(ellipse(0.78, 0.92, rx: 0.12, ry: 0.06))
        ground()
    }
    mutating func dubaiFront() {
        // Burj Al Arab: mast, sail and helipad.
        add(rect(0.895, 0.905, top: 0.22))
        var sail = Path()
        sail.move(to: p(0.90, 0.24)); sail.addQuadCurve(to: p(0.985, 0.95), control: p(0.99, 0.40)); sail.addLine(to: p(0.90, 0.95)); sail.closeSubpath()
        add(sail)
        add(ellipse(0.885, 0.40, rx: 0.02, ry: 0.012))
        water(from: 0.62, to: 0.88)
        ground()
    }

    // MARK: Sharjah — Eye of the Emirates, Al Noor Mosque, heritage arcade

    mutating func sharjahBack() {
        add(ring(0.82, 0.42, 0.30, width: 0.025))
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * .pi * 2
            add(line((0.82, 0.42), (0.82 + cos(a) * 0.30 * h / w, 0.42 + sin(a) * 0.30), width: 0.008))
        }
        add(poly([(0.80, 0.42), (0.76, 1), (0.78, 1)])); add(poly([(0.84, 0.42), (0.88, 1), (0.86, 1)]))
        for (x0, x1, top) in [(0.62, 0.68, 0.62), (0.94, 1.0, 0.56)] as [(CGFloat, CGFloat, CGFloat)] { add(rect(x0, x1, top: top)) }
    }
    mutating func sharjahMid() {
        // Al Noor Mosque: central dome, half domes, pencil minarets.
        add(rect(0.16, 0.54, top: 0.66))
        dome(0.35, base: 0.52, r: 0.15)
        dome(0.25, base: 0.62, r: 0.07, finial: false); dome(0.45, base: 0.62, r: 0.07, finial: false)
        for x in [0.14, 0.56] as [CGFloat] {
            add(rect(x - 0.008, x + 0.008, top: 0.18))
            add(poly([(x - 0.008, 0.18), (x, 0.04), (x + 0.008, 0.18)]))
            add(rect(x - 0.014, x + 0.014, top: 0.36, bottom: 0.38))
        }
        ground()
    }
    mutating func sharjahFront() {
        // A heritage arcade: columns under pointed arches.
        add(rect(0.0, 1.0, top: 0.86))
        for k in 0..<12 {
            let x = CGFloat(k) / 12 + 0.02
            var arch = Path()
            arch.move(to: p(x, 0.96)); arch.addLine(to: p(x, 0.91))
            arch.addQuadCurve(to: p(x + 0.022, 0.885), control: p(x, 0.885)); arch.addQuadCurve(to: p(x + 0.044, 0.91), control: p(x + 0.044, 0.885))
            arch.addLine(to: p(x + 0.044, 0.96)); arch.closeSubpath()
            cut(arch)
        }
        ground()
    }

    // MARK: Ajman — corniche towers, Ajman Museum and wind tower, a dhow among mangroves

    mutating func ajmanBack() {
        for (x0, x1, top) in [(0.60, 0.64, 0.46), (0.65, 0.69, 0.36), (0.70, 0.74, 0.52), (0.76, 0.80, 0.40), (0.82, 0.86, 0.56)]
            as [(CGFloat, CGFloat, CGFloat)] { add(rect(x0, x1, top: top)) }
        mangrove(0.93, 0.18)
    }
    mutating func ajmanMid() {
        fortTower(0.06, 0.16, top: 0.40, merlons: 3)
        add(rect(0.16, 0.34, top: 0.62))
        // Barjeel: a wind tower with its vents.
        add(rect(0.26, 0.32, top: 0.34))
        for k in 0..<3 { cut(rect(0.268 + CGFloat(k) * 0.017, 0.276 + CGFloat(k) * 0.017, top: 0.38, bottom: 0.52)) }
        ground()
    }
    mutating func ajmanFront() {
        // Dhow: curved hull, mast and lateen sail.
        var hull = Path()
        hull.move(to: p(0.38, 0.80)); hull.addLine(to: p(0.70, 0.78))
        hull.addQuadCurve(to: p(0.64, 0.90), control: p(0.69, 0.88)); hull.addLine(to: p(0.44, 0.90))
        hull.addQuadCurve(to: p(0.38, 0.80), control: p(0.40, 0.88)); hull.closeSubpath()
        add(hull)
        add(rect(0.535, 0.545, top: 0.28, bottom: 0.80))
        var sail = Path()
        sail.move(to: p(0.44, 0.74)); sail.addQuadCurve(to: p(0.62, 0.24), control: p(0.47, 0.36)); sail.addLine(to: p(0.60, 0.74)); sail.closeSubpath()
        add(sail)
        mangrove(0.86, 0.2)
        water()
    }

    // MARK: Umm Al Quwain — lagoon islands, the old fort, flamingos

    mutating func uaqBack() {
        for (cx, rx) in [(0.62, 0.12), (0.84, 0.09), (0.97, 0.06)] as [(CGFloat, CGFloat)] { add(ellipse(cx, 0.84, rx: rx, ry: 0.05)) }
        mangrove(0.70, 0.14); mangrove(0.86, 0.12)
    }
    mutating func uaqMid() {
        // The fort's round watchtower and its walls.
        add(rect(0.10, 0.20, top: 0.36)); add(ellipse(0.15, 0.36, rx: 0.05, ry: 0.03))
        for k in 0..<4 { add(rect(0.102 + CGFloat(k) * 0.026, 0.115 + CGFloat(k) * 0.026, top: 0.30, bottom: 0.36)) }
        fortTower(0.20, 0.40, top: 0.62, merlons: 6)
        fortTower(0.38, 0.44, top: 0.48, merlons: 2)
        cut(Path(ellipseIn: CGRect(x: 0.285 * w, y: 0.76 * h, width: 0.03 * w, height: 0.08 * h))); cut(rect(0.285, 0.315, top: 0.80, bottom: 0.96))
        ground()
    }
    mutating func uaqFront() {
        // Two flamingos wading.
        for (x, s) in [(0.60, 1.0), (0.70, 0.85)] as [(CGFloat, CGFloat)] {
            add(ellipse(x, 0.62, rx: 0.035 * s, ry: 0.07 * s))
            var neck = Path()
            neck.move(to: p(x + 0.025 * s, 0.58)); neck.addCurve(to: p(x + 0.03 * s, 0.34), control1: p(x + 0.07 * s, 0.50), control2: p(x - 0.01 * s, 0.42))
            add(neck.strokedPath(StrokeStyle(lineWidth: 0.018 * h, lineCap: .round)))
            add(circle(x + 0.03 * s, 0.33, 0.025 * s))
            add(line((x + 0.03 * s, 0.33), (x + 0.05 * s, 0.37), width: 0.014))
            add(line((x, 0.68), (x, 0.92), width: 0.008)); add(line((x + 0.01, 0.68), (x + 0.02, 0.92), width: 0.008))
        }
        water()
    }

    // MARK: Ras Al Khaimah — the sun, Jebel Jais and its zipline, Dhayah fort on its hill

    mutating func rakBack() {
        add(circle(0.80, 0.24, 0.10))
        mountains([(0.0, 0.70), (0.12, 0.52), (0.24, 0.62), (0.40, 0.40), (0.56, 0.58), (0.72, 0.50), (0.88, 0.66), (1.0, 0.56)])
    }
    mutating func rakMid() {
        mountains([(0.0, 0.86), (0.18, 0.46), (0.30, 0.62), (0.44, 0.10), (0.54, 0.40), (0.62, 0.32), (0.80, 0.80), (1.0, 0.90)])
        // The zipline from the summit.
        add(line((0.44, 0.10), (0.98, 0.56), width: 0.008))
    }
    mutating func rakFront() {
        add(ellipse(0.74, 1.0, rx: 0.16, ry: 0.22))
        fortTower(0.70, 0.76, top: 0.62, merlons: 3)
        add(rect(0.76, 0.80, top: 0.72))
        palm(0.10, top: 0.58); palm(0.18, top: 0.66, size: 0.8)
        ground()
    }

    // MARK: Fujairah — Hajar mountains, Al Bidyah Mosque, Fujairah Fort, palms by the sea

    mutating func fujairahBack() {
        mountains([(0.0, 0.50), (0.14, 0.24), (0.28, 0.44), (0.42, 0.18), (0.58, 0.40), (0.74, 0.28), (0.88, 0.46), (1.0, 0.36)])
    }
    mutating func fujairahMid() {
        // Al Bidyah Mosque: a low block with four small domes.
        add(rect(0.08, 0.28, top: 0.66))
        for (x, y) in [(0.13, 0.66), (0.23, 0.66), (0.16, 0.60), (0.20, 0.60)] as [(CGFloat, CGFloat)] { add(circle(x, y, 0.05)) }
        // Fujairah Fort: round towers and a square keep.
        fortTower(0.50, 0.62, top: 0.56, merlons: 4)
        add(rect(0.46, 0.51, top: 0.46)); add(ellipse(0.485, 0.46, rx: 0.025, ry: 0.03))
        add(rect(0.62, 0.68, top: 0.42)); add(ellipse(0.65, 0.42, rx: 0.03, ry: 0.035))
        ground()
    }
    mutating func fujairahFront() {
        palm(0.78, top: 0.46); palm(0.86, top: 0.56, size: 0.85); palm(0.93, top: 0.50, size: 0.9)
        water(from: 0, to: 0.72)
        ground()
    }
}

/// The three layers of a city, light to strong, in the theme's own colours.
struct GhafCityScene: View {
    let city: String
    let accent: Color
    let glow: Color
    var strength: Double = 1

    var body: some View {
        ZStack {
            ForEach([false, true], id: \.self) { foliage in
                GhafCitySkyline(city: city, layer: .back, foliage: foliage).fill(glow.opacity(0.35 * strength))
                GhafCitySkyline(city: city, layer: .mid, foliage: foliage)
                    .fill(LinearGradient(colors: [glow, accent], startPoint: .top, endPoint: .bottom).opacity(0.75 * strength))
                GhafCitySkyline(city: city, layer: .front, foliage: foliage).fill(accent.opacity(strength))
            }
        }
        // Shapes that rest on the ground (hills) never spill past the scene.
        .clipped()
        // Landmarks keep their real left-right arrangement in Arabic too.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// The city behind every screen: a tall, faint scene in the middle of the background that is
/// always slightly alive. A glow breathes, the near layer sways like wind through palms and
/// mangroves, the far layer drifts, and coastal cities have a dhow riding the swell.
/// Still when Reduce Motion is on. Hidden for Graphite, which has no city.
struct GhafCityBackdrop: View {
    let theme: GhafTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where each coastal scene's water is (x from…to, in scene units), so a dhow rides on it, not in the sky.
    private static let water: [String: ClosedRange<CGFloat>] = ["Dubai": 0.64...0.86, "Umm Al Quwain": 0.08...0.5, "Fujairah": 0.08...0.6]

    var body: some View {
        let city = GhafTheme.canonical(theme.name)
        if city != "Graphite" {
            TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                scene(city: city, t: t)
            }
            .frame(height: 360)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                         .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func scene(city: String, t: Double) -> some View {
        let strength = theme.isDark ? 0.2 : 0.15
        // Only palms and mangroves move; buildings, forts and hills stay exactly as drawn.
        let sway = 0.03 * sin(t * 0.8) + 0.012 * sin(t * 2.1)
        return GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                // A soft light behind the landmarks that slowly breathes and wanders.
                RadialGradient(colors: [theme.glow.opacity(theme.isDark ? 0.35 : 0.28), .clear], center: .center,
                               startRadius: 0, endRadius: 220)
                    .scaleEffect(1 + 0.08 * sin(t * 0.45))
                    .offset(x: 40 * sin(t * 0.12), y: 30 + 14 * cos(t * 0.17))
                if theme.isDark { stars(t: t, w: w, h: h) }
                birds(t: t, w: w, h: h).foregroundStyle(theme.accent.opacity(2.5 * strength))
                layer(city, .back, theme.glow.opacity(0.35 * strength), sway: sway * 0.5)
                layer(city, .mid, LinearGradient(colors: [theme.glow, theme.accent], startPoint: .top, endPoint: .bottom).opacity(0.75 * strength),
                      sway: sway * 0.75)
                if let span = Self.water[city] {
                    // Bobs on the swell and drifts slowly along its stretch of water.
                    let x = (span.lowerBound + (span.upperBound - span.lowerBound) * (0.5 + 0.4 * sin(t * 0.05))) * w
                    GhafDhow()
                        .fill(theme.accent.opacity(0.9 * strength))
                        .frame(width: h * 0.13, height: h * 0.11)
                        .rotationEffect(.degrees(2.5 * sin(t * 0.9)), anchor: .bottom)
                        .position(x: x, y: h * 0.86 + 2.5 * sin(t * 1.3))
                }
                layer(city, .front, theme.accent.opacity(strength), sway: sway)
            }
        }
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
    }

    private func layer<S: ShapeStyle>(_ city: String, _ layer: GhafCitySkyline.Layer, _ style: S, sway: Double) -> some View {
        ZStack {
            GhafCitySkyline(city: city, layer: layer).fill(style)
            GhafCitySkyline(city: city, layer: layer, foliage: true).fill(style)
                .modifier(GhafWindSway(amount: sway))
        }
    }

    /// Three birds crossing the sky every couple of minutes, wings beating slowly.
    private func birds(t: Double, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let progress = CGFloat(((t + Double(index) * 4) / 110).truncatingRemainder(dividingBy: 1))
                GhafBird(flap: 0.5 + 0.5 * sin(t * 4 + Double(index)))
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 14 - CGFloat(index) * 2, height: 6)
                    .position(x: -30 + progress * (w + 60) - CGFloat(index) * 16,
                              y: h * (0.18 + 0.05 * CGFloat(index)) + 4 * sin(t * 0.6 + Double(index)))
            }
        }
    }

    /// A few stars that twinkle in dark mode.
    private func stars(t: Double, w: CGFloat, h: CGFloat) -> some View {
        let spots: [(CGFloat, CGFloat)] = [(0.12, 0.12), (0.3, 0.22), (0.52, 0.08), (0.68, 0.18), (0.86, 0.1), (0.94, 0.28), (0.42, 0.3)]
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { index, spot in
                Circle().fill(theme.glow)
                    .frame(width: 2.5, height: 2.5)
                    .opacity(0.25 + 0.5 * max(0, sin(t * 0.9 + Double(index) * 1.7)))
                    .position(x: spot.0 * w, y: spot.1 * h)
            }
        }
    }
}

/// A distant bird: two wing strokes whose tips rise and fall with `flap` (0…1).
struct GhafBird: Shape {
    var flap: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tipY = rect.minY + rect.height * (0.1 + 0.8 * flap)
        path.move(to: CGPoint(x: rect.minX, y: tipY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.width * 0.3 + rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: tipY), control: CGPoint(x: rect.width * 0.7 + rect.minX, y: rect.minY))
        return path
    }
}

/// Leans palms and mangroves from their base, so their tops move in the wind while their roots stay put.
struct GhafWindSway: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: -amount * size.height, ty: 0))
    }
}

/// A dhow: a curved wooden hull and a lateen sail on a raked mast.
struct GhafDhow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var hull = Path()
        hull.move(to: p(0.0, 0.70))
        hull.addQuadCurve(to: p(1.0, 0.66), control: p(0.55, 0.74))
        hull.addQuadCurve(to: p(0.80, 0.94), control: p(0.94, 0.86))
        hull.addLine(to: p(0.22, 0.94))
        hull.addQuadCurve(to: p(0.0, 0.70), control: p(0.08, 0.88))
        var sail = Path()
        sail.move(to: p(0.20, 0.08))
        sail.addQuadCurve(to: p(0.86, 0.62), control: p(0.70, 0.18))
        sail.addLine(to: p(0.38, 0.62))
        sail.closeSubpath()
        var mast = Path()
        mast.move(to: p(0.46, 0.70)); mast.addLine(to: p(0.42, 0.20))
        return hull.union(sail).union(mast.strokedPath(StrokeStyle(lineWidth: w * 0.03, lineCap: .round)))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(GhafTheme.themeNames, id: \.self) { name in
                GhafCityScene(city: name, accent: .brown, glow: .orange).frame(height: 110)
            }
        }
        .padding()
    }
}
