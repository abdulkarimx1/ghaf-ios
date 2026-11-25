import SwiftUI

/// Geist (OFL, Shared/Fonts) with tabular figures: every number in the app and its widgets.
/// Arabic-Indic digits are not in Geist, so those glyphs fall back to the system font.
func ghafNumberFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .custom("Geist-Regular", size: size).weight(weight == .regular ? .medium : weight).monospacedDigit()
}
