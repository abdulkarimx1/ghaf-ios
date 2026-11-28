import SwiftUI
import UIKit
#if DEBUG
import os
#endif

struct GhafSaveSplash: View {
    let title: String
    let amount: Decimal
    let currency: String
    let detail: String
    let theme: GhafTheme
    let languageCode: String
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var soundStarted = false
    @State private var tickAppeared = false
    @State private var dismissed = false
#if DEBUG
    private let debugLogger = Logger(subsystem: "com.ghaf.app", category: "SaveSplash")
#endif

    private let blurEnd = 0.35

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: dismissed)) { context in
            let realElapsed = max(0, context.date.timeIntervalSince(startedAt ?? context.date))
            let speed = reduceMotion ? 4.3 / 3.8 : 1.0
            let endTime = reduceMotion ? 4.3 : 4.5
            let elapsed = realElapsed * speed
            let t = min(elapsed, endTime)
            let returnProgress = easeInOut(segment(t, reduceMotion ? 3.9 : 3.85, endTime))
            let dimDepth = easeOut(segment(t, 0, blurEnd)) * (1 - returnProgress)
            let rise = reduceMotion ? (t >= blurEnd ? 0.2 : 0.0) : segment(t, blurEnd, 3.85)
            let surge = reduceMotion ? 0.0 : rise
            let doneStart = reduceMotion ? 2.35 : 2.18
            let tickStart = reduceMotion ? 2.6 : 2.43
            let doneProgress = segment(t, doneStart, reduceMotion ? 2.95 : 2.8)
            let doneOpacity = min(1, doneProgress * 2.2) * (1 - returnProgress)
            let ring = easeOut(segment(t, doneStart, reduceMotion ? 2.8 : 2.63))
            let tick = easeOut(segment(t, tickStart, reduceMotion ? 2.95 : 2.8))
            let savingFade = reduceMotion ? segment(t, 2.0, 2.2) : segment(t, doneStart - 0.2, doneStart)
            let savingOpacity = segment(t, 0.15, 0.45) * (1 - savingFade)
            let shaderFade = reduceMotion
                ? segment(t, blurEnd, 0.8) * (1 - easeInOut(segment(t, 3.9, endTime)))
                : segment(t, blurEnd - 0.05, blurEnd + 0.25) * (1 - easeInOut(segment(t, 3.85, endTime)))

            ZStack {
                // The splash is presented from a sheet; a clear cover background lets that
                // sheet show through during the shader's partial-alpha entrance.
                theme.background
                    .ignoresSafeArea()
                if t < endTime {
                    Color(theme.isDark ? UIColor(red: 0.031, green: 0.035, blue: 0.043, alpha: 1)
                                       : UIColor(red: 0.949, green: 0.953, blue: 0.961, alpha: 1))
                        .opacity((theme.isDark ? 0.5 + 0.42 * surge : 0.35 + 0.3 * surge) * dimDepth)
                        .ignoresSafeArea()
                    glow(t: t, rise: rise, surge: surge, fade: shaderFade, speed: speed)
                        .accessibilityHidden(true)
                    if t < (reduceMotion ? 2.2 : 3.85) {
                        HStack(spacing: 9) {
                            ProgressView().tint(theme.primaryText)
                            Text(languageCode == "ar" ? "جارٍ الحفظ…" : "Saving…")
                                .font(GhafTypography.body(15, languageCode: languageCode, weight: .medium))
                        }
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(savingOpacity)
                        .accessibilityElement(children: .combine)
                    }
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().trim(from: 0, to: ring).stroke(theme.primaryText,
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
                        HStack(spacing: 7) {
                            GhafCurrencyIcon(currency: currency, size: 25)
                            Text(GhafMoneyLabel.formatter(languageCode: languageCode, currency: currency).string(from: amount as NSDecimalNumber)
                                 ?? NSDecimalNumber(decimal: amount).stringValue)
                                .font(GhafTypography.number(30, weight: .bold))
                        }
                        .foregroundStyle(theme.primaryText)
                        Text(detail).font(GhafTypography.body(13, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(doneOpacity)
                    .offset(y: (1 - easeOut(doneProgress)) * 14)
                    .scaleEffect(0.92 + 0.08 * spring(doneProgress))
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
#if DEBUG
                debugLogger.debug("added sound play elapsed=\(realElapsed, format: .fixed(precision: 3))s")
#endif
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
        .onAppear {
            startedAt = Date()
#if DEBUG
            debugLogger.debug("splash start uptime=\(ProcessInfo.processInfo.systemUptime, format: .fixed(precision: 3))s")
#endif
        }
    }

    private func glow(t: Double, rise: Double, surge: Double, fade: Double, speed: Double) -> some View {
        let colors = GhafTheme.cities[theme.name] ?? GhafTheme.cities["Graphite"]!
        let shader = ShaderLibrary.default.ghafSaveGlow(
            .boundingRect,
            .float(Float(reduceMotion ? 0 : t / speed * 0.30)),
            .float(Float(t)),
            .float(Float(rise)),
            .float(Float(surge)),
            .float(Float(fade)),
            .float(0.7),
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

    private func segment(_ value: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (value - a) / (b - a))) }
    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private func spring(_ x: Double) -> Double { x >= 1 ? 1 : 1 - exp(-6 * x) * cos(9 * x) }
}
