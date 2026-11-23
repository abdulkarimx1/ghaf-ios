import SwiftUI
import UIKit

struct GhafSaveSplash: View {
    let title: String
    let amount: String
    let detail: String
    let theme: GhafTheme
    let languageCode: String
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var soundStarted = false
    @State private var tickAppeared = false
    @State private var dismissed = false

    private let speed = 4.3 / 3.8
    private let endTime = 4.3
    private let blurEnd = 0.35
    private let riseEnd = 1.35
    private let surgeStart = 2.0
    private let surgeEnd = 2.55
    private let fadeEnd = 3.1
    private let holdEnd = 3.9
    private let doneStart = 2.35
    private let tickStart = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: dismissed)) { context in
            let realElapsed = max(0, context.date.timeIntervalSince(startedAt ?? context.date))
            let elapsed = realElapsed * speed
            let t = min(elapsed, endTime)
            let dimDepth = smooth(t, 0, blurEnd) * (1 - smooth(t, holdEnd, endTime))
            let surge = smooth(t, surgeStart, surgeEnd)
            let done = smooth(t, doneStart, 2.95) * (1 - smooth(t, holdEnd, endTime))
            let tick = smooth(t, tickStart, 2.95)
            let rise = reduceMotion ? (t >= blurEnd ? 1.0 : 0.0) : easeOut(smooth(t, blurEnd - 0.05, riseEnd))
            let shaderFade = reduceMotion
                ? smooth(t, blurEnd, 0.8) * (1 - smooth(t, holdEnd, endTime))
                : smooth(t, blurEnd - 0.05, blurEnd + 0.25) * (1 - smooth(t, surgeEnd - 0.15, fadeEnd))

            ZStack {
                Color.clear
                if t < endTime {
                    Color(theme.isDark ? UIColor.black : UIColor(red: 0.949, green: 0.953, blue: 0.961, alpha: 1))
                        .opacity((theme.isDark ? 0.5 + 0.42 * surge : 0.35 + 0.3 * surge) * dimDepth)
                        .ignoresSafeArea()
                    glow(t: t, rise: rise, surge: reduceMotion ? 0 : easeInOut(surge), fade: shaderFade)
                        .accessibilityHidden(true)
                    if t < surgeStart {
                        HStack(spacing: 9) {
                            ProgressView().tint(theme.primaryText)
                            Text(languageCode == "ar" ? "جارٍ الحفظ…" : "Saving…")
                                .font(GhafTypography.body(15, languageCode: languageCode, weight: .medium))
                        }
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().trim(from: 0, to: tick).stroke(theme.primaryText,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Path { path in
                                path.move(to: CGPoint(x: 17, y: 29))
                                path.addLine(to: CGPoint(x: 25, y: 37))
                                path.addLine(to: CGPoint(x: 42, y: 20))
                            }
                            .trim(from: 0, to: tick)
                            .stroke(theme.primaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        }
                        .frame(width: 58, height: 58)
                        Text(title).font(GhafTypography.heading(21, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                            .accessibilityLabel("Transaction added")
                        Text(amount).font(GhafTypography.number(30, weight: .bold)).foregroundStyle(theme.primaryText)
                        Text(detail).font(GhafTypography.body(13, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(min(1, done * 2.2))
                    .offset(y: (1 - easeOut(done)) * 14)
                    .scaleEffect(0.92 + 0.08 * spring(done))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
            .onChange(of: t >= tickStart) { _, visible in
                guard visible, !tickAppeared else { return }
                tickAppeared = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .onChange(of: realElapsed >= GhafSounds.addedDelay) { _, ready in
                guard ready, !soundStarted else { return }
                soundStarted = true
                GhafSounds.shared.play(.added)
            }
            .onChange(of: t >= endTime) { _, ended in
                guard ended, !dismissed else { return }
                dismissed = true
                finish()
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("Transaction added")
        .onAppear { startedAt = Date() }
    }

    private func glow(t: Double, rise: Double, surge: Double, fade: Double) -> some View {
        let colors = GhafTheme.cities[theme.name] ?? GhafTheme.cities["Graphite"]!
        let shader = ShaderLibrary.default.ghafSaveGlow(
            .boundingRect,
            .float(Float(reduceMotion ? 0 : t / speed * 0.30)),
            .float(Float(rise)),
            .float(Float(surge)),
            .float(Float(fade)),
            .float(0.25),
            .float(0.5),
            .float(theme.isDark ? 0 : 1),
            shaderColor(colors.accent.light),
            shaderColor(colors.glow.light),
            shaderColor(colors.accent.dark),
            shaderColor(colors.glow.dark)
        )
        return Rectangle().fill(.white).colorEffect(shader)
            .blendMode(theme.isDark ? .screen : .normal)
            .ignoresSafeArea()
    }

    private func rgba(_ color: Color) -> SIMD4<Float> {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD4(Float(red), Float(green), Float(blue), Float(alpha))
    }

    private func shaderColor(_ color: Color) -> Shader.Argument {
        let components = rgba(color)
        return .float4(components.x, components.y, components.z, components.w)
    }

    private func smooth(_ value: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(1, max(0, (value - a) / (b - a)))
        return x * x * (3 - 2 * x)
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private func spring(_ x: Double) -> Double { x >= 1 ? 1 : 1 - exp(-6 * x) * cos(9 * x) }
}
