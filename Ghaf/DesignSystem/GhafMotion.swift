import SwiftUI

/// Tactile press for custom buttons: a quick spring squash, softened when Reduce Motion is on.
struct GhafPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1) // owner pick 1.31
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            // A light tap felt on press, so every Ghaf button answers the finger.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == GhafPressStyle {
    static var ghafPress: GhafPressStyle { GhafPressStyle() }
}

/// One-time staggered rise-in for a screen's sections. Skipped under Reduce Motion.
private struct GhafEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var isSnapshot: Bool {
#if DEBUG
        GhafScreenshotFixture.snapshotTestingEnabled
#else
        false
#endif
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion || isSnapshot ? 1 : 0)
            .offset(y: shown || reduceMotion || isSnapshot ? 0 : 18)
            .onAppear {
                guard !shown, !isSnapshot else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func ghafEntrance(_ index: Int) -> some View { modifier(GhafEntrance(index: index)) }
}
