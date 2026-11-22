import SwiftUI

struct GhafSuccessSplash: View {
    let title: String
    let subtitle: String
    let theme: GhafTheme
    let languageCode: String
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var complete = false
    @State private var glowUp = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.background.ignoresSafeArea()
                if !complete && !reduceMotion {
                    Circle().fill(theme.glow.opacity(theme.isDark ? 0.30 : 0.15))
                        .frame(width: proxy.size.width * 0.9).blur(radius: 64)
                        .position(x: proxy.size.width * 0.5, y: glowUp ? proxy.size.height * 0.86 : proxy.size.height * 1.12)
                    Circle().fill(theme.accent.opacity(theme.isDark ? 0.18 : 0.10))
                        .frame(width: proxy.size.width * 0.72).blur(radius: 74)
                        .position(x: proxy.size.width * 0.28, y: glowUp ? proxy.size.height * 0.94 : proxy.size.height * 1.18)
                }
                VStack(spacing: 12) {
                    if complete {
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                        Text(title).font(GhafTypography.heading(21, languageCode: languageCode)).foregroundStyle(theme.primaryText)
                        Text(subtitle).font(GhafTypography.body(14, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    } else {
                        ProgressView().tint(theme.accent)
                        Text(languageCode == "ar" ? "جارٍ التسجيل…" : "Logging…").font(GhafTypography.body(15, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
            .contentShape(Rectangle()).onTapGesture { finish() }
            .sensoryFeedback(.success, trigger: complete)
            .task {
                withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.6)) { glowUp = true }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.3)) { complete = true }
                try? await Task.sleep(for: .milliseconds(1_200))
                finish()
            }
        }
        .ignoresSafeArea()
    }
}
