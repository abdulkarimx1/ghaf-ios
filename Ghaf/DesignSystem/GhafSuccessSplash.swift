import SwiftUI
import UIKit

struct GhafSuccessSplash: View {
    let title: String
    let subtitle: String
    let theme: GhafTheme
    let languageCode: String
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var complete = false
    @State private var glowUp = false
    @State private var glowMorph = false
    @State private var glowPastTop = false
    @State private var dismissed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.background.opacity(complete ? 1 : 0.55).ignoresSafeArea()
                if !reduceMotion {
                    Circle().fill(theme.accent.opacity(theme.isDark ? 0.34 : 0.20))
                        .frame(width: proxy.size.width * 1.12).blur(radius: 72)
                        .scaleEffect(glowMorph ? 1.05 : 0.92)
                        .opacity(glowPastTop ? 0 : 1)
                        .position(x: proxy.size.width * 0.48,
                                  y: proxy.size.height * (glowPastTop ? -0.28 : (glowUp ? 0.38 : 1.40)))
                    Circle().fill(complementaryGlow.opacity(theme.isDark ? 0.28 : 0.16))
                        .frame(width: proxy.size.width * 0.82).blur(radius: 82)
                        .scaleEffect(glowMorph ? 0.94 : 1.04)
                        .opacity(glowPastTop ? 0 : 1)
                        .position(x: proxy.size.width * (glowPastTop ? 0.72 : 0.24),
                                  y: proxy.size.height * (glowPastTop ? -0.18 : (glowUp ? 0.50 : 1.52)))
                }
                VStack(spacing: 12) {
                    if complete {
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                            .matchedGeometryEffect(id: "success-dot", in: successNamespace)
                        Text(title).font(GhafTypography.heading(21, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                        Text(subtitle).font(GhafTypography.body(14, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    } else {
                        ProgressView().tint(theme.accent)
                            .matchedGeometryEffect(id: "success-dot", in: successNamespace)
                        Text(languageCode == "ar" ? "جارٍ الحفظ…" : "Saving…").font(GhafTypography.body(15, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .contentShape(Rectangle()).onTapGesture { dismissOnce() }
            .sensoryFeedback(.success, trigger: complete)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !dismissed else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: 1.0)) { glowUp = true }
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) { glowMorph = true }
                }
                try? await Task.sleep(for: .milliseconds(1_000))
                guard !dismissed else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.25)) { complete = true }
                GhafSounds.shared.play(.added)
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.6)) { glowPastTop = true }
                try? await Task.sleep(for: .milliseconds(1_800))
                dismissOnce()
            }
        }
        .ignoresSafeArea()
    }

    @Namespace private var successNamespace

    /// Rotate the theme accent hue to get its complement; no animation colour is hard-coded.
    private var complementaryGlow: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(theme.accent).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let complement = (hue + 0.5).truncatingRemainder(dividingBy: 1)
        return Color(hue: Double(complement), saturation: Double(max(saturation, 0.34) * 0.72),
                     brightness: theme.isDark ? 0.92 : 0.72)
    }

    private func dismissOnce() {
        guard !dismissed else { return }
        dismissed = true
        withAnimation(.easeOut(duration: 0.25)) { finish() }
    }
}
