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

    /// A UAE city: accent, a tinted canvas for each mode, and a second colour for glows and gradients.
    /// Light accents keep at least 4.5:1 on white.
    struct City {
        let accent: (light: Color, dark: Color)
        let glow: (light: Color, dark: Color)
        let canvas: (light: Color, dark: Color)
        let card: (light: Color, dark: Color)
        let en: String
        let ar: String
    }

    static let cities: [String: City] = [
        "Abu Dhabi": City(accent: (rgb(0x8A5A24), rgb(0xE0B472)), glow: (rgb(0xC9A15B), rgb(0xF3D29A)),
                          canvas: (rgb(0xF5F1EA), rgb(0x0F0D0A)), card: (rgb(0xFFFDF9), rgb(0x1B1814)),
                          en: "Qasr Al Hosn sand and gold", ar: "رمال قصر الحصن وذهبه"),
        "Dubai": City(accent: (rgb(0x1F5FAE), rgb(0x7FB2F2)), glow: (rgb(0x5BA8E0), rgb(0xB9DBFF)),
                      canvas: (rgb(0xEEF2F7), rgb(0x0A0D12)), card: (rgb(0xFCFDFF), rgb(0x161A21)),
                      en: "Glass towers and Gulf sky", ar: "أبراج الزجاج وسماء الخليج"),
        "Sharjah": City(accent: (rgb(0x6B3FA0), rgb(0xBC9BEA)), glow: (rgb(0xB07CD8), rgb(0xE3CCFF)),
                        canvas: (rgb(0xF3F0F7), rgb(0x0E0C12)), card: (rgb(0xFEFCFF), rgb(0x1A1720)),
                        en: "Arts, heritage and lanterns", ar: "الفنون والتراث والفوانيس"),
        "Ajman": City(accent: (rgb(0x13704F), rgb(0x5FD3A0)), glow: (rgb(0x3FB283), rgb(0xA8F0CF)),
                      canvas: (rgb(0xEDF3EF), rgb(0x0A0F0D)), card: (rgb(0xFBFEFC), rgb(0x151C19)),
                      en: "The corniche and the creek", ar: "الكورنيش والخور"),
        "Umm Al Quwain": City(accent: (rgb(0x0F6E7D), rgb(0x62CFDD)), glow: (rgb(0x3AB3C2), rgb(0xA6EEF6)),
                              canvas: (rgb(0xECF4F5), rgb(0x090F10)), card: (rgb(0xFBFEFE), rgb(0x141C1E)),
                              en: "Lagoons and quiet water", ar: "البحيرات والمياه الهادئة"),
        "Ras Al Khaimah": City(accent: (rgb(0xA4492A), rgb(0xF0956E)), glow: (rgb(0xE07A4F), rgb(0xFFC3A5)),
                               canvas: (rgb(0xF6EFEB), rgb(0x110C0A)), card: (rgb(0xFFFCFA), rgb(0x1E1714)),
                               en: "Jebel Jais at sunset", ar: "جبل جيس عند الغروب"),
        "Fujairah": City(accent: (rgb(0x55622A), rgb(0xBFD07A)), glow: (rgb(0x8FA34A), rgb(0xE0EDA8)),
                         canvas: (rgb(0xF1F2EC), rgb(0x0D0E0A)), card: (rgb(0xFDFDF9), rgb(0x191B14)),
                         en: "Hajar mountains and the sea", ar: "جبال الحجر والبحر"),
        "Graphite": City(accent: (rgb(0x111214), rgb(0xF2F2F4)), glow: (rgb(0x6B6E76), rgb(0xC8CAD0)),
                         canvas: (rgb(0xF2F3F5), rgb(0x0B0C0E)), card: (.white, rgb(0x17181B)),
                         en: "Quiet and neutral", ar: "هادئ ومحايد")
    ]

    static let themeNames = ["Abu Dhabi", "Dubai", "Sharjah", "Ajman", "Umm Al Quwain", "Ras Al Khaimah", "Fujairah", "Graphite"]

    /// Themes that were removed map to the closest city, so existing users keep a similar look.
    static func canonical(_ name: String) -> String {
        switch name {
        case "Dawn": "Ras Al Khaimah"
        case "Dusk": "Sharjah"
        case "Oasis": "Ajman"
        default: cities[name] == nil ? "Abu Dhabi" : name
        }
    }

    /// Second colour of the theme, for glows and gradients next to the accent.
    var glow: Color {
        let city = Self.cities[name] ?? Self.cities["Abu Dhabi"]!
        return isDark ? city.glow.dark : city.glow.light
    }

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
        let resolvedName = canonical(name)
        let city = cities[resolvedName]!
        let accent = isDark ? city.accent.dark : city.accent.light

        if isDark {
            return GhafTheme(
                name: resolvedName, isDark: true,
                background: city.canvas.dark,
                surface: city.card.dark,
                elevatedSurface: city.card.dark.opacity(0.6),
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
            background: city.canvas.light,
            surface: city.card.light,
            elevatedSurface: city.canvas.light,
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
    static let cardPadding: CGFloat = 16
    static let heroPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let rowRadius: CGFloat = 18
    static let sectionSpacing: CGFloat = 22
}
