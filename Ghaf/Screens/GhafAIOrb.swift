import SwiftUI
import UIKit

/// One recognizer owns the entire orb interaction: quick release speaks, a held press
/// produces one haptic at 450 ms and opens text on release.
struct GhafOrbPressGesture: ViewModifier {
    var onTap: () -> Void
    var onHold: () -> Void
    @State private var pressedAt: Date?
    @State private var didHaptic = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { _ in
                    if pressedAt == nil {
                        let start = Date.now
                        pressedAt = start
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            guard pressedAt == start, !didHaptic else { return }
                            didHaptic = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .onEnded { _ in
                    let duration = pressedAt.map { Date.now.timeIntervalSince($0) } ?? 0
                    pressedAt = nil
                    defer { didHaptic = false }
                    if duration < 0.45 { onTap() }
                    else { onHold() }
                }
        )
    }
}

/// Ghaf AI's orb: a glass sphere holding a slow "liquid light" of three soft colour blobs from the city
/// theme. Each state moves differently so it reads without words: idle drifts, listening gathers and swells
/// with the voice, thinking swirls into a turning arc, speaking sends ripples out with Ghaf's own voice.
/// Reduce Motion stops the movement; the state still shows through brightness.
struct GhafAIOrb: View {
    enum Mood { case idle, listening, thinking, speaking }

    let theme: GhafTheme
    var mood: Mood = .idle
    /// Microphone or voice loudness 0…1 while listening or speaking.
    var level: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isVisible)) { context in
            GhafAIOrbFace(theme: theme, mood: mood, level: CGFloat(min(max(level, 0), 1)),
                          time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate,
                          still: reduceMotion)
        }
        .animation(.smooth(duration: 0.5), value: mood)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityHidden(true)
    }
}

/// One frame of the orb, drawn in a single Canvas pass. `time` drives every movement, so the tab icon
/// can render chosen frames of it.
struct GhafAIOrbFace: View {
    let theme: GhafTheme
    let mood: GhafAIOrb.Mood
    let level: CGFloat
    let time: Double
    var still = false
    var halo = true

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                // Outside the Canvas, so the blur fades out instead of stopping at the frame's edge.
                if halo {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: side * 0.86, height: side * 0.86)
                        .blur(radius: side * 0.14)
                        .opacity(mood == .idle ? 0.16 : 0.28) // soft, so the particles keep their contrast
                }
                orb
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// 1200 points spread evenly over a sphere (Fibonacci lattice), computed once.
    private static let points: [(x: Double, y: Double, z: Double)] = {
        let n = 1200, golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - (Double(i) + 0.5) / Double(n) * 2
            let ring = (1 - y * y).squareRoot(), a = golden * Double(i)
            return (cos(a) * ring, y, sin(a) * ring)
        }
    }()

    /// Owner 1.31 AURA pick: particle sphere, 1200 particles, size 0.9, spin 0.55, react 0.6, theme tint + glow.
    /// Particles use the theme accent at full strength so they stay visible on white as well as on dark.
    private var orb: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * (halo ? 0.4 : 0.48)
            let t = still ? 0.6 : time
            let spin: Double = 0.55 * (mood == .thinking ? 3.2 : mood == .idle ? 1 : 1.6)
            let react = 0.6 * Double(level)
            let angle = t * spin, tilt = 0.35 + (mood == .thinking ? 0.25 * sin(t * 1.3) : 0)
            let (ca, sa, ct, st) = (cos(angle), sin(angle), cos(tilt), sin(tilt))
            // Owner 1.31: brighter (was pale on device), and a share of particles drifts past the sphere's edge.
            let dot = max(0.9, side * 0.0105)
            let voice = mood == .listening || mood == .speaking
            for (i, p) in Self.points.enumerated() {
                // Spin about Y, then tilt about X so the poles read as a globe.
                let x1 = p.x * ca + p.z * sa, z1 = -p.x * sa + p.z * ca
                let y2 = p.y * ct - z1 * st, z2 = p.y * st + z1 * ct
                var r = radius
                switch mood {
                case .idle: r *= 1 + 0.02 * sin(t * 1.6)
                case .listening: r *= 1 + react * 0.18 + 0.015 * sin(t * 6 + p.y * 4)
                case .thinking: r *= 1 + 0.04 * sin(t * 4 + p.x * 6)
                case .speaking: r *= 1 + (0.05 + react * 0.2) * max(0, sin(t * 7 - (1 - p.y) * 5))
                }
                // Every 5th particle floats out and back; voice pushes them further, silence leaves a slow breath.
                if i % 5 == 0 {
                    let phase = Double(i) * 0.618
                    r *= 1 + (0.05 + (voice ? react * 0.35 : 0)) * (0.5 + 0.5 * sin(t * 0.8 + phase))
                }
                if voice { r *= 1 + 0.012 * sin(t * 2.2) }
                r = min(r, side * 0.5 - dot) // never clipped by the canvas edge
                let depth = (z2 + 1) / 2 // 0 back … 1 front
                let px = center.x + x1 * r, py = center.y + y2 * r
                let d = dot * (0.55 + depth * 0.9)
                context.fill(Circle().path(in: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d)),
                             with: .color(theme.accent.opacity(0.4 + depth * 0.6)))
            }
        }
    }
}
