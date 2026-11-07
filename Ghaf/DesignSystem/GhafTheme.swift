import SwiftUI

enum GhafBudgetStatus {
    case comfortable
    case close
    case over
}

struct GhafTheme {
    let name: String
    let background: Color
    let surface: Color
    let elevatedSurface: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accentContrast: Color
    let debit: Color
    let credit: Color
    let comfortable: Color
    let close: Color
    let over: Color
    let outline: Color

    static func resolve(
        name: String,
        appearanceMode: String,
        systemIsDark: Bool
    ) -> GhafTheme {
        let isDark: Bool
        switch appearanceMode {
        case "Dark": isDark = true
        case "Light": isDark = false
        default: isDark = systemIsDark
        }

        let cityPalettes: [String: (background: Color, surface: Color, text: Color, secondary: Color, accent: Color, darkAccent: Color)] = [
            "Abu Dhabi": (
                Color(red: 0.95, green: 0.92, blue: 0.85), Color(red: 0.99, green: 0.97, blue: 0.92),
                Color(red: 0.22, green: 0.19, blue: 0.15), Color(red: 0.49, green: 0.44, blue: 0.36),
                Color(red: 0.53, green: 0.36, blue: 0.20), Color(red: 0.83, green: 0.65, blue: 0.39)
            ),
            "Dubai": (
                Color(red: 0.91, green: 0.94, blue: 0.97), Color(red: 0.98, green: 0.99, blue: 1.0),
                Color(red: 0.12, green: 0.17, blue: 0.24), Color(red: 0.40, green: 0.47, blue: 0.56),
                Color(red: 0.16, green: 0.34, blue: 0.55), Color(red: 0.48, green: 0.68, blue: 0.91)
            ),
            "Sharjah": (
                Color(red: 0.94, green: 0.92, blue: 0.90), Color(red: 0.99, green: 0.98, blue: 0.96),
                Color(red: 0.20, green: 0.18, blue: 0.22), Color(red: 0.48, green: 0.44, blue: 0.50),
                Color(red: 0.39, green: 0.29, blue: 0.47), Color(red: 0.70, green: 0.57, blue: 0.82)
            ),
            "Ajman": (
                Color(red: 0.89, green: 0.94, blue: 0.91), Color(red: 0.97, green: 0.99, blue: 0.97),
                Color(red: 0.12, green: 0.23, blue: 0.19), Color(red: 0.37, green: 0.49, blue: 0.42),
                Color(red: 0.13, green: 0.43, blue: 0.33), Color(red: 0.37, green: 0.73, blue: 0.57)
            ),
            "Umm Al Quwain": (
                Color(red: 0.89, green: 0.95, blue: 0.96), Color(red: 0.97, green: 0.99, blue: 0.99),
                Color(red: 0.10, green: 0.23, blue: 0.26), Color(red: 0.36, green: 0.50, blue: 0.54),
                Color(red: 0.13, green: 0.43, blue: 0.49), Color(red: 0.38, green: 0.73, blue: 0.79)
            ),
            "Ras Al Khaimah": (
                Color(red: 0.93, green: 0.92, blue: 0.89), Color(red: 0.99, green: 0.98, blue: 0.95),
                Color(red: 0.22, green: 0.21, blue: 0.19), Color(red: 0.48, green: 0.46, blue: 0.42),
                Color(red: 0.53, green: 0.31, blue: 0.20), Color(red: 0.82, green: 0.53, blue: 0.35)
            ),
            "Fujairah": (
                Color(red: 0.90, green: 0.94, blue: 0.97), Color(red: 0.98, green: 0.99, blue: 1.0),
                Color(red: 0.12, green: 0.20, blue: 0.28), Color(red: 0.38, green: 0.47, blue: 0.56),
                Color(red: 0.17, green: 0.39, blue: 0.58), Color(red: 0.42, green: 0.68, blue: 0.88)
            )
        ]

        if let palette = cityPalettes[name] {
            return GhafTheme(
                name: name,
                background: isDark ? Color(red: 0.075, green: 0.09, blue: 0.095) : palette.background,
                surface: isDark ? Color(red: 0.12, green: 0.145, blue: 0.15) : palette.surface,
                elevatedSurface: isDark ? Color(red: 0.17, green: 0.195, blue: 0.20) : .white,
                primaryText: isDark ? Color(red: 0.94, green: 0.95, blue: 0.93) : palette.text,
                secondaryText: isDark ? Color(red: 0.67, green: 0.72, blue: 0.71) : palette.secondary,
                accent: isDark ? palette.darkAccent : palette.accent,
                accentContrast: isDark ? Color(red: 0.08, green: 0.10, blue: 0.10) : .white,
                debit: isDark ? Color(red: 0.96, green: 0.55, blue: 0.46) : Color(red: 0.72, green: 0.32, blue: 0.27),
                credit: isDark ? Color(red: 0.48, green: 0.82, blue: 0.63) : Color(red: 0.22, green: 0.52, blue: 0.37),
                comfortable: isDark ? Color(red: 0.48, green: 0.82, blue: 0.63) : Color(red: 0.22, green: 0.52, blue: 0.37),
                close: Color(red: 0.88, green: 0.65, blue: 0.31),
                over: isDark ? Color(red: 0.96, green: 0.48, blue: 0.42) : Color(red: 0.72, green: 0.30, blue: 0.26),
                outline: isDark ? Color(red: 0.27, green: 0.33, blue: 0.33) : palette.accent.opacity(0.16)
            )
        }

        switch name {
        case "Dawn":
            return isDark
                ? GhafTheme(
                    name: "Dawn",
                    background: Color(red: 0.12, green: 0.12, blue: 0.11),
                    surface: Color(red: 0.19, green: 0.18, blue: 0.16),
                    elevatedSurface: Color(red: 0.24, green: 0.23, blue: 0.20),
                    primaryText: Color(red: 0.96, green: 0.93, blue: 0.86),
                    secondaryText: Color(red: 0.69, green: 0.67, blue: 0.61),
                    accent: Color(red: 0.86, green: 0.67, blue: 0.42),
                    accentContrast: Color(red: 0.16, green: 0.14, blue: 0.11),
                    debit: Color(red: 0.91, green: 0.55, blue: 0.43),
                    credit: Color(red: 0.64, green: 0.79, blue: 0.54),
                    comfortable: Color(red: 0.64, green: 0.79, blue: 0.54),
                    close: Color(red: 0.94, green: 0.72, blue: 0.38),
                    over: Color(red: 0.91, green: 0.50, blue: 0.40),
                    outline: Color(red: 0.34, green: 0.32, blue: 0.28)
                )
                : GhafTheme(
                    name: "Dawn",
                    background: Color(red: 0.96, green: 0.93, blue: 0.86),
                    surface: Color(red: 0.99, green: 0.97, blue: 0.92),
                    elevatedSurface: .white,
                    primaryText: Color(red: 0.20, green: 0.17, blue: 0.13),
                    secondaryText: Color(red: 0.48, green: 0.43, blue: 0.35),
                    accent: Color(red: 0.53, green: 0.37, blue: 0.22),
                    accentContrast: Color(red: 0.99, green: 0.97, blue: 0.92),
                    debit: Color(red: 0.70, green: 0.34, blue: 0.26),
                    credit: Color(red: 0.31, green: 0.52, blue: 0.35),
                    comfortable: Color(red: 0.31, green: 0.52, blue: 0.35),
                    close: Color(red: 0.73, green: 0.48, blue: 0.19),
                    over: Color(red: 0.70, green: 0.34, blue: 0.26),
                    outline: Color(red: 0.85, green: 0.81, blue: 0.73)
                )
        case "Dusk":
            return isDark
                ? GhafTheme(
                    name: "Dusk",
                    background: Color(red: 0.07, green: 0.08, blue: 0.10),
                    surface: Color(red: 0.13, green: 0.15, blue: 0.18),
                    elevatedSurface: Color(red: 0.18, green: 0.20, blue: 0.24),
                    primaryText: Color(red: 0.94, green: 0.95, blue: 0.97),
                    secondaryText: Color(red: 0.65, green: 0.69, blue: 0.75),
                    accent: Color(red: 0.62, green: 0.74, blue: 0.98),
                    accentContrast: Color(red: 0.06, green: 0.09, blue: 0.16),
                    debit: Color(red: 0.96, green: 0.53, blue: 0.47),
                    credit: Color(red: 0.43, green: 0.83, blue: 0.63),
                    comfortable: Color(red: 0.43, green: 0.83, blue: 0.63),
                    close: Color(red: 0.98, green: 0.74, blue: 0.39),
                    over: Color(red: 0.96, green: 0.48, blue: 0.43),
                    outline: Color(red: 0.26, green: 0.30, blue: 0.37)
                )
                : GhafTheme(
                    name: "Dusk",
                    background: Color(red: 0.93, green: 0.94, blue: 0.96),
                    surface: Color(red: 0.98, green: 0.98, blue: 0.99),
                    elevatedSurface: .white,
                    primaryText: Color(red: 0.12, green: 0.15, blue: 0.21),
                    secondaryText: Color(red: 0.42, green: 0.47, blue: 0.56),
                    accent: Color(red: 0.22, green: 0.34, blue: 0.58),
                    accentContrast: .white,
                    debit: Color(red: 0.76, green: 0.31, blue: 0.27),
                    credit: Color(red: 0.22, green: 0.55, blue: 0.40),
                    comfortable: Color(red: 0.22, green: 0.55, blue: 0.40),
                    close: Color(red: 0.76, green: 0.49, blue: 0.16),
                    over: Color(red: 0.76, green: 0.31, blue: 0.27),
                    outline: Color(red: 0.82, green: 0.85, blue: 0.90)
                )
        default:
            return isDark
                ? GhafTheme(
                    name: "Oasis",
                    background: Color(red: 0.055, green: 0.105, blue: 0.085),
                    surface: Color(red: 0.09, green: 0.17, blue: 0.135),
                    elevatedSurface: Color(red: 0.13, green: 0.22, blue: 0.17),
                    primaryText: Color(red: 0.94, green: 0.96, blue: 0.89),
                    secondaryText: Color(red: 0.65, green: 0.73, blue: 0.65),
                    accent: Color(red: 0.78, green: 0.91, blue: 0.43),
                    accentContrast: Color(red: 0.09, green: 0.16, blue: 0.12),
                    debit: Color(red: 0.94, green: 0.55, blue: 0.43),
                    credit: Color(red: 0.67, green: 0.85, blue: 0.48),
                    comfortable: Color(red: 0.78, green: 0.91, blue: 0.43),
                    close: Color(red: 0.95, green: 0.73, blue: 0.37),
                    over: Color(red: 0.94, green: 0.48, blue: 0.39),
                    outline: Color(red: 0.22, green: 0.34, blue: 0.27)
                )
                : GhafTheme(
                    name: "Oasis",
                    background: Color(red: 0.94, green: 0.94, blue: 0.87),
                    surface: Color(red: 0.985, green: 0.98, blue: 0.94),
                    elevatedSurface: .white,
                    primaryText: Color(red: 0.075, green: 0.16, blue: 0.12),
                    secondaryText: Color(red: 0.37, green: 0.46, blue: 0.39),
                    accent: Color(red: 0.10, green: 0.28, blue: 0.21),
                    accentContrast: Color(red: 0.98, green: 0.97, blue: 0.91),
                    debit: Color(red: 0.71, green: 0.35, blue: 0.27),
                    credit: Color(red: 0.27, green: 0.52, blue: 0.34),
                    comfortable: Color(red: 0.27, green: 0.52, blue: 0.34),
                    close: Color(red: 0.73, green: 0.49, blue: 0.18),
                    over: Color(red: 0.71, green: 0.35, blue: 0.27),
                    outline: Color(red: 0.81, green: 0.85, blue: 0.78)
                )
        }
    }

    func statusColor(_ status: GhafBudgetStatus) -> Color {
        switch status {
        case .comfortable: comfortable
        case .close: close
        case .over: over
        }
    }
}

enum GhafTypeScale {
    static let display = Font.custom("IBMPlexSans-Regular", size: 42).weight(.bold)
    static let largeTitle = Font.custom("IBMPlexSans-Regular", size: 30).weight(.bold)
    static let title = Font.custom("IBMPlexSans-Regular", size: 22).weight(.semibold)
    static let body = Font.custom("IBMPlexSans-Regular", size: 16)
    static let caption = Font.custom("IBMPlexSans-Regular", size: 12).weight(.medium)
}

struct GhafPrimaryButtonStyle: ButtonStyle {
    let theme: GhafTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("IBMPlexSans-Regular", size: 16).weight(.semibold))
            .foregroundStyle(theme.accentContrast)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .padding(.horizontal, 18)
            .background(
                theme.accent.opacity(configuration.isPressed ? 0.84 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
