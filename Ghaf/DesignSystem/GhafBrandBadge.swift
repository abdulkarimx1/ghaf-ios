import SwiftUI

/// Company marks from Simple Icons (CC0, simpleicons.org v13.21.0), bundled as template SVGs in
/// Assets.xcassets/Brands so every logo shares one monochrome style and is tinted like Ghaf's own icons.
struct GhafBrand {
    let asset: String
    let color: Color

    /// Most specific keywords first so "Apple Music" is not matched as "Apple".
    private static let catalog: [(slug: String, hex: UInt32, keywords: [String])] = [
        ("applemusic", 0xFA243C, ["apple music"]), ("appletv", 0x000000, ["apple tv"]),
        ("icloud", 0x3693F3, ["icloud"]), ("apple", 0x000000, ["apple.com", "apple one", "apple"]),
        ("youtubemusic", 0xFF0000, ["youtube music"]), ("youtube", 0xFF0000, ["youtube"]),
        ("primevideo", 0x1F2E3E, ["prime video"]), ("amazonprime", 0x00A8E1, ["amazon prime", "amazon"]),
        ("netflix", 0xE50914, ["netflix"]), ("spotify", 0x1ED760, ["spotify"]),
        ("openai", 0x412991, ["openai", "chatgpt", "chat gpt"]), ("claude", 0xD97757, ["claude"]),
        ("anthropic", 0x191919, ["anthropic"]), ("adobe", 0xFF0000, ["adobe"]),
        ("playstation", 0x0070D1, ["playstation", "psn"]), ("nintendo", 0xE60012, ["nintendo"]),
        ("dropbox", 0x0061FF, ["dropbox"]), ("canva", 0x00C4CC, ["canva"]), ("notion", 0x000000, ["notion"]),
        ("linkedin", 0x0A66C2, ["linkedin"]), ("patreon", 0x000000, ["patreon"]), ("tidal", 0x000000, ["tidal"]),
        ("crunchyroll", 0xF47521, ["crunchyroll"]), ("audible", 0xF8991C, ["audible"]),
        ("duolingo", 0x58CC02, ["duolingo"]), ("headspace", 0xF47D31, ["headspace"]),
        ("deliveroo", 0x00CCBC, ["deliveroo"]), ("github", 0x181717, ["github"]), ("figma", 0xF24E1E, ["figma"]),
        ("google", 0x4285F4, ["google"])
    ]

    static func match(_ name: String?) -> GhafBrand? {
        guard let name = name?.lowercased(), !name.isEmpty else { return nil }
        guard let entry = catalog.first(where: { $0.keywords.contains { name.contains($0) } }) else { return nil }
        let hex = entry.hex
        return GhafBrand(
            asset: "Brand-\(entry.slug)",
            color: Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        )
    }
}

/// Same circle as `GhafIconBadge`, holding a monochrome company mark, or the name's first letter when no mark is known.
struct GhafBrandBadge: View {
    let name: String
    let fallbackTint: Color
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let brand = GhafBrand.match(name)
        // Every mark is monochrome in the text colour, like the rest of Ghaf's icons.
        let tint = Color.primary
        Group {
            if let brand {
                Image(brand.asset).resizable().scaledToFit().frame(width: size * 0.44, height: size * 0.44)
            } else {
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
        .background(tint.opacity(colorScheme == .dark ? 0.12 : 0.07), in: Circle())
        .accessibilityHidden(true)
    }

}
