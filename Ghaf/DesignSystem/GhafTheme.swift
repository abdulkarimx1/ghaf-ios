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
        case "Dark":
            isDark = true

        case "Light":
            isDark = false

        default:
            isDark = systemIsDark
        }

        switch name {

        case "Dawn":

            if isDark {
                return GhafTheme(
                    name: "Dawn",
                    background: Color(red: 0.14, green: 0.12, blue: 0.10),
                    surface: Color(red: 0.20, green: 0.17, blue: 0.14),
                    elevatedSurface: Color(red: 0.26, green: 0.22, blue: 0.18),
                    primaryText: Color(red: 0.96, green: 0.91, blue: 0.82),
                    secondaryText: Color(red: 0.72, green: 0.66, blue: 0.56),
                    accent: Color(red: 0.76, green: 0.57, blue: 0.37),
                    accentContrast: Color(red: 0.16, green: 0.12, blue: 0.09),
                    debit: Color(red: 0.89, green: 0.56, blue: 0.48),
                    credit: Color(red: 0.57, green: 0.77, blue: 0.60),
                    comfortable: Color(red: 0.57, green: 0.77, blue: 0.60),
                    close: Color(red: 0.91, green: 0.70, blue: 0.38),
                    over: Color(red: 0.89, green: 0.46, blue: 0.40),
                    outline: Color(red: 0.34, green: 0.28, blue: 0.22)
                )
            }

            return GhafTheme(
                name: "Dawn",
                background: Color(red: 0.96, green: 0.93, blue: 0.86),
                surface: Color(red: 0.99, green: 0.97, blue: 0.92),
                elevatedSurface: .white,
                primaryText: Color(red: 0.19, green: 0.16, blue: 0.12),
                secondaryText: Color(red: 0.47, green: 0.42, blue: 0.34),
                accent: Color(red: 0.48, green: 0.35, blue: 0.24),
                accentContrast: .white,
                debit: Color(red: 0.69, green: 0.31, blue: 0.26),
                credit: Color(red: 0.25, green: 0.48, blue: 0.34),
                comfortable: Color(red: 0.25, green: 0.48, blue: 0.34),
                close: Color(red: 0.72, green: 0.48, blue: 0.20),
                over: Color(red: 0.69, green: 0.31, blue: 0.26),
                outline: Color(red: 0.84, green: 0.80, blue: 0.72)
            )

        case "Dusk":

            if isDark {
                return GhafTheme(
                    name: "Dusk",
                    background: Color(red: 0.12, green: 0.10, blue: 0.09),
                    surface: Color(red: 0.19, green: 0.16, blue: 0.14),
                    elevatedSurface: Color(red: 0.25, green: 0.21, blue: 0.18),
                    primaryText: Color(red: 0.94, green: 0.88, blue: 0.80),
                    secondaryText: Color(red: 0.71, green: 0.63, blue: 0.54),
                    accent: Color(red: 0.72, green: 0.52, blue: 0.35),
                    accentContrast: Color(red: 0.12, green: 0.10, blue: 0.09),
                    debit: Color(red: 0.88, green: 0.54, blue: 0.46),
                    credit: Color(red: 0.62, green: 0.77, blue: 0.59),
                    comfortable: Color(red: 0.62, green: 0.77, blue: 0.59),
                    close: Color(red: 0.90, green: 0.69, blue: 0.37),
                    over: Color(red: 0.88, green: 0.45, blue: 0.39),
                    outline: Color(red: 0.33, green: 0.27, blue: 0.23)
                )
            }

            return GhafTheme(
                name: "Dusk",
                background: Color(red: 0.91, green: 0.87, blue: 0.81),
                surface: Color(red: 0.96, green: 0.93, blue: 0.88),
                elevatedSurface: Color(red: 0.99, green: 0.97, blue: 0.93),
                primaryText: Color(red: 0.20, green: 0.16, blue: 0.13),
                secondaryText: Color(red: 0.48, green: 0.40, blue: 0.34),
                accent: Color(red: 0.40, green: 0.29, blue: 0.23),
                accentContrast: .white,
                debit: Color(red: 0.67, green: 0.30, blue: 0.25),
                credit: Color(red: 0.29, green: 0.48, blue: 0.34),
                comfortable: Color(red: 0.29, green: 0.48, blue: 0.34),
                close: Color(red: 0.73, green: 0.48, blue: 0.19),
                over: Color(red: 0.67, green: 0.30, blue: 0.25),
                outline: Color(red: 0.77, green: 0.71, blue: 0.63)
            )

        default:

            if isDark {
                return GhafTheme(
                    name: "Oasis",
                    background: Color(red: 0.09, green: 0.16, blue: 0.12),
                    surface: Color(red: 0.14, green: 0.23, blue: 0.17),
                    elevatedSurface: Color(red: 0.19, green: 0.29, blue: 0.22),
                    primaryText: Color(red: 0.91, green: 0.95, blue: 0.88),
                    secondaryText: Color(red: 0.66, green: 0.76, blue: 0.66),
                    accent: Color(red: 0.58, green: 0.73, blue: 0.52),
                    accentContrast: Color(red: 0.09, green: 0.16, blue: 0.12),
                    debit: Color(red: 0.87, green: 0.55, blue: 0.46),
                    credit: Color(red: 0.58, green: 0.79, blue: 0.60),
                    comfortable: Color(red: 0.58, green: 0.79, blue: 0.60),
                    close: Color(red: 0.91, green: 0.71, blue: 0.39),
                    over: Color(red: 0.87, green: 0.46, blue: 0.39),
                    outline: Color(red: 0.28, green: 0.38, blue: 0.29)
                )
            }

            return GhafTheme(
                name: "Oasis",
                background: Color(red: 0.90, green: 0.93, blue: 0.87),
                surface: Color(red: 0.96, green: 0.97, blue: 0.93),
                elevatedSurface: .white,
                primaryText: Color(red: 0.13, green: 0.24, blue: 0.17),
                secondaryText: Color(red: 0.39, green: 0.48, blue: 0.39),
                accent: Color(red: 0.27, green: 0.43, blue: 0.31),
                accentContrast: .white,
                debit: Color(red: 0.66, green: 0.34, blue: 0.28),
                credit: Color(red: 0.27, green: 0.48, blue: 0.34),
                comfortable: Color(red: 0.27, green: 0.48, blue: 0.34),
                close: Color(red: 0.72, green: 0.49, blue: 0.22),
                over: Color(red: 0.66, green: 0.34, blue: 0.28),
                outline: Color(red: 0.79, green: 0.84, blue: 0.77)
            )
        }
    }

    func statusColor(_ status: GhafBudgetStatus) -> Color {

        switch status {
        case .comfortable:
            return comfortable
        case .close:
            return close
        case .over:
            return over
        }
    }
}

enum GhafTypeScale {

    static let display = Font.system(
        size: 42,
        weight: .heavy,
        design: .rounded
    )

    static let largeTitle = Font.system(
        size: 30,
        weight: .bold,
        design: .rounded
    )

    static let title = Font.system(
        size: 22,
        weight: .bold
    )

    static let body = Font.system(
        size: 16,
        weight: .regular
    )

    static let caption = Font.system(
        size: 12,
        weight: .medium
    )
}

struct GhafPrimaryButtonStyle: ButtonStyle {

    let theme: GhafTheme

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.accentContrast)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                theme.accent.opacity(
                    configuration.isPressed ? 0.75 : 1
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
}
