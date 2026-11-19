import SwiftUI

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
                        .opacity(mood == .idle ? 0.45 : 0.75)
                }
                orb
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var orb: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // The halo needs room, so the sphere sits inside the frame.
            let radius = side * (halo ? 0.4 : 0.48)
            let t = time
            let speed: Double = switch mood { case .idle: 0.35; case .listening: 0.9; case .thinking: 2.1; case .speaking: 1.2 }
            let energy: CGFloat = switch mood { case .idle: 0.0; case .listening: 0.35 + level * 0.65; case .thinking: 0.6; case .speaking: 0.3 + level * 0.7 }
            let breathe = still ? 1 : 1 + 0.025 * sin(t * 1.9) + energy * 0.06
            let r = radius * breathe

            // Ripples leave the sphere while Ghaf speaks.
            if mood == .speaking && !still {
                for index in 0..<3 {
                    let phase = (t * 0.7 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    let ring = r * (1 + CGFloat(phase) * (0.35 + level * 0.25))
                    context.stroke(Circle().path(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
                                   with: .color(theme.glow.opacity((1 - phase) * 0.5)), lineWidth: max(1, side * 0.008))
                }
            }

            let sphere = Circle().path(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(sphere, with: .radialGradient(Gradient(colors: [theme.accent.opacity(0.55), GhafAIView.night]),
                                                       center: center, startRadius: 0, endRadius: r))

            // Liquid light: three blurred blobs on slow Lissajous paths, clipped to the glass.
            context.drawLayer { layer in
                layer.clip(to: sphere)
                layer.addFilter(.blur(radius: r * 0.22))
                let blobs: [(Color, Double, Double, CGFloat)] = [
                    (theme.accent, 0.0, 1.0, 0.62),
                    (theme.glow, 2.1, 1.3, 0.5),
                    (.white.opacity(0.85), 4.2, 0.8, 0.3)
                ]
                for (color, offset, rate, size) in blobs {
                    let a = t * speed * rate + offset
                    let pos: CGPoint
                    if mood == .thinking {
                        // A turning swirl: the blobs chase each other round the inside of the rim.
                        pos = CGPoint(x: center.x + cos(a) * r * 0.42, y: center.y + sin(a) * r * 0.42)
                    } else {
                        // Listening pulls them in towards the voice; idle lets them wander.
                        let reach = r * (0.38 - energy * 0.22)
                        pos = CGPoint(x: center.x + cos(a) * reach + sin(a * 0.7) * reach * 0.4,
                                      y: center.y + sin(a * 1.3) * reach)
                    }
                    let br = r * size * (1 + energy * 0.25)
                    layer.fill(Circle().path(in: CGRect(x: pos.x - br, y: pos.y - br, width: br * 2, height: br * 2)),
                               with: .color(color))
                }
            }

            // Rim light: a bright arc that turns, a comet while thinking.
            let arc = Path { path in
                path.addArc(center: center, radius: r * 0.97, startAngle: .radians(t * speed * 1.4),
                            endAngle: .radians(t * speed * 1.4 + (mood == .thinking ? 2.4 : 1.4)), clockwise: false)
            }
            context.stroke(arc, with: .color(.white.opacity(0.55 + Double(energy) * 0.4)),
                           style: StrokeStyle(lineWidth: max(1, side * 0.012), lineCap: .round))
            context.stroke(sphere, with: .color(theme.glow.opacity(0.45)), lineWidth: max(0.6, side * 0.005))

            // Glass highlight, fixed so the sphere keeps its shape while the light moves inside.
            var shine = context
            shine.addFilter(.blur(radius: r * 0.08))
            shine.fill(Ellipse().path(in: CGRect(x: center.x - r * 0.55, y: center.y - r * 0.72, width: r * 0.5, height: r * 0.22)),
                       with: .color(.white.opacity(0.45)))
        }
    }
}
