import SwiftUI

enum GhafBudgetStatus {
    case comfortable
    case close
    case over
}

/// One neutral surface system for every theme: soft grey canvas, white cards, near-black ink.
/// A theme only chooses its accent, so all themes share the same contrast and spacing.
struct GhafTheme {
    let name: String
    let isDark: Bool
    let background: Color
    /// Card fill (white in light mode).
    let surface: Color
    /// Fills inside cards: chips, fields, segmented tracks.
    let elevatedSurface: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accentContrast: Color
    /// The one dark "insight" card and the floating action surfaces.
    let ink: Color
    let inkText: Color
    /// Debit/credit colours that keep contrast on the dark ink card in both modes.
    let inkDebit = rgb(0xFF8A7A)
    let inkCredit = rgb(0x4FD58E)
    let debit: Color
    let credit: Color
    let comfortable: Color
    let close: Color
    let over: Color
    let outline: Color
    let shadow: Color

    /// Accent pairs (light mode, dark mode). Light accents keep at least 4.5:1 on white.
    private static let accents: [String: (light: Color, dark: Color)] = [
        "Abu Dhabi": (rgb(0x8A5A24), rgb(0xE0B472)),
        "Dubai": (rgb(0x1F5FAE), rgb(0x7FB2F2)),
        "Sharjah": (rgb(0x6B3FA0), rgb(0xBC9BEA)),
        "Ajman": (rgb(0x13704F), rgb(0x5FD3A0)),
        "Umm Al Quwain": (rgb(0x0F6E7D), rgb(0x62CFDD)),
        "Ras Al Khaimah": (rgb(0xA4492A), rgb(0xF0956E)),
        "Fujairah": (rgb(0x2C5C8A), rgb(0x8DBBE6)),
        "Dawn": (rgb(0x9A5B1E), rgb(0xF0B36A)),
        "Dusk": (rgb(0x3A4FB0), rgb(0x9DABFF)),
        "Oasis": (rgb(0x1E6A45), rgb(0x9BE07A)),
        "Graphite": (rgb(0x111214), rgb(0xF2F2F4))
    ]

    static let themeNames = ["Graphite", "Abu Dhabi", "Dubai", "Sharjah", "Ajman", "Umm Al Quwain",
                             "Ras Al Khaimah", "Fujairah", "Dawn", "Dusk", "Oasis"]

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
        let resolvedName = accents[name] == nil ? "Oasis" : name
        let pair = accents[resolvedName]!
        let accent = isDark ? pair.dark : pair.light

        if isDark {
            return GhafTheme(
                name: resolvedName, isDark: true,
                background: rgb(0x0B0C0E),
                surface: rgb(0x17181B),
                elevatedSurface: rgb(0x222327),
                primaryText: rgb(0xF4F4F6),
                secondaryText: rgb(0x9C9EA6),
                accent: accent,
                accentContrast: rgb(0x0B0C0E),
                ink: rgb(0x232429),
                inkText: rgb(0xF4F4F6),
                debit: rgb(0xFF8A7A),
                credit: rgb(0x4FD58E),
                comfortable: rgb(0x4FD58E),
                close: rgb(0xF5B851),
                over: rgb(0xFF7A6B),
                outline: Color.white.opacity(0.08),
                shadow: .clear
            )
        }
        return GhafTheme(
            name: resolvedName, isDark: false,
            background: rgb(0xF2F3F5),
            surface: .white,
            elevatedSurface: rgb(0xF2F3F5),
            primaryText: rgb(0x111214),
            secondaryText: rgb(0x6B6E76),
            accent: accent,
            accentContrast: .white,
            ink: rgb(0x111214),
            inkText: .white,
            debit: rgb(0xC2412D),
            credit: rgb(0x14874F),
            comfortable: rgb(0x14874F),
            close: rgb(0xB86E00),
            over: rgb(0xC2412D),
            outline: Color.black.opacity(0.06),
            shadow: Color.black.opacity(0.06)
        )
    }

    func statusColor(_ status: GhafBudgetStatus) -> Color {
        switch status {
        case .comfortable: comfortable
        case .close: close
        case .over: over
        }
    }
}

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// Spacing and corner radii shared by every screen.
enum GhafMetrics {
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let rowRadius: CGFloat = 18
    static let sectionSpacing: CGFloat = 22
}
