import SwiftUI

/// Banks issuing cards in the UAE, with the brand colours Ghaf uses to draw a card face when no real
/// card image is chosen. Matched from the account's bank or name, so most accounts get the right look
/// without any setup. Colours are approximations for illustration; no logos are used.
struct GhafUAEBank: Identifiable {
    let id: String
    let en: String
    let ar: String
    let aliases: [String]
    let colors: (UInt32, UInt32)

    static let all: [GhafUAEBank] = [
        .init(id: "enbd", en: "Emirates NBD", ar: "بنك الإمارات دبي الوطني", aliases: ["emirates nbd", "enbd", "الإمارات دبي"], colors: (0x0B2B5C, 0x1E5AA8)),
        .init(id: "liv", en: "Liv", ar: "ليف", aliases: ["liv"], colors: (0x5B2BC4, 0xC04BD8)),
        .init(id: "fab", en: "First Abu Dhabi Bank", ar: "بنك أبوظبي الأول", aliases: ["first abu dhabi", "fab", "أبوظبي الأول"], colors: (0x18264E, 0x2F5BA8)),
        .init(id: "adcb", en: "ADCB", ar: "بنك أبوظبي التجاري", aliases: ["adcb", "abu dhabi commercial", "أبوظبي التجاري"], colors: (0x9E0B1F, 0xD6243A)),
        .init(id: "hayyak", en: "Hayyak", ar: "حياك", aliases: ["hayyak"], colors: (0x5A1A8C, 0xB2367A)),
        .init(id: "dib", en: "Dubai Islamic Bank", ar: "بنك دبي الإسلامي", aliases: ["dubai islamic", "dib", "دبي الإسلامي"], colors: (0x0A5A3C, 0x1E8A5C)),
        .init(id: "adib", en: "ADIB", ar: "مصرف أبوظبي الإسلامي", aliases: ["adib", "abu dhabi islamic", "أبوظبي الإسلامي"], colors: (0x00467F, 0x1A86C7)),
        .init(id: "ei", en: "Emirates Islamic", ar: "الإمارات الإسلامي", aliases: ["emirates islamic", "الإمارات الإسلامي"], colors: (0x0B5D57, 0x2A9A8C)),
        .init(id: "mashreq", en: "Mashreq", ar: "المشرق", aliases: ["mashreq", "المشرق", "neo"], colors: (0xC24A10, 0xF2862E)),
        .init(id: "rak", en: "RAKBANK", ar: "بنك رأس الخيمة", aliases: ["rakbank", "rak bank", "rakbank", "رأس الخيمة الوطني"], colors: (0x9C0A14, 0xE0242F)),
        .init(id: "cbd", en: "Commercial Bank of Dubai", ar: "بنك دبي التجاري", aliases: ["cbd", "commercial bank of dubai", "دبي التجاري"], colors: (0x003D7A, 0x0D74C8)),
        .init(id: "wio", en: "Wio", ar: "ويو", aliases: ["wio"], colors: (0x0E0E12, 0x3A3F52)),
        .init(id: "ruya", en: "Ruya", ar: "رؤيا", aliases: ["ruya", "رؤيا"], colors: (0x5C3B12, 0xB9873A)),
        .init(id: "mbank", en: "Al Maryah Community Bank", ar: "بنك المارية المجتمعي", aliases: ["al maryah", "mbank", "maryah", "المارية"], colors: (0x5E0F2E, 0xA82852)),
        .init(id: "sib", en: "Sharjah Islamic Bank", ar: "مصرف الشارقة الإسلامي", aliases: ["sharjah islamic", "sib", "الشارقة الإسلامي"], colors: (0x0C4A2E, 0x2E8A4E)),
        .init(id: "ajman", en: "Ajman Bank", ar: "مصرف عجمان", aliases: ["ajman bank", "مصرف عجمان"], colors: (0x4A2A6E, 0x8E5AB8)),
        .init(id: "nbf", en: "National Bank of Fujairah", ar: "بنك الفجيرة الوطني", aliases: ["nbf", "fujairah"], colors: (0x0A3E5C, 0x2B7FA3)),
        .init(id: "uab", en: "United Arab Bank", ar: "البنك العربي المتحد", aliases: ["united arab bank", "uab"], colors: (0x123A6B, 0x3B79B8)),
        .init(id: "cbi", en: "Commercial Bank International", ar: "البنك التجاري الدولي", aliases: ["cbi", "commercial bank international"], colors: (0x0F3F6A, 0xD08A1F)),
        .init(id: "hsbc", en: "HSBC UAE", ar: "إتش إس بي سي", aliases: ["hsbc"], colors: (0x8E0A0A, 0xDB0011)),
        .init(id: "sc", en: "Standard Chartered", ar: "ستاندرد تشارترد", aliases: ["standard chartered", "stanchart"], colors: (0x0A5D3A, 0x0072AA)),
        .init(id: "citi", en: "Citibank UAE", ar: "سيتي بنك", aliases: ["citi"], colors: (0x0A2F6B, 0x1F7AC9)),
        .init(id: "arab", en: "Arab Bank", ar: "البنك العربي", aliases: ["arab bank", "البنك العربي"], colors: (0x0B4A3A, 0x2E8F6A)),
        .init(id: "invest", en: "InvestBank", ar: "بنك الاستثمار", aliases: ["investbank", "invest bank"], colors: (0x2A2A2E, 0x8A6A2E)),
        .init(id: "eib", en: "Emirates Investment Bank", ar: "بنك الإمارات للاستثمار", aliases: ["emirates investment bank", "eibank"], colors: (0x1A1A1E, 0x6A5A3A)),
        .init(id: "alhilal", en: "Al Hilal Bank", ar: "مصرف الهلال", aliases: ["al hilal", "alhilal", "الهلال"], colors: (0x1B1F4A, 0x4A4F8E)),
        .init(id: "bos", en: "Bank of Sharjah", ar: "بنك الشارقة", aliases: ["bank of sharjah", "بنك الشارقة"], colors: (0x0E3A6B, 0x2E7CC0)),
        .init(id: "nbq", en: "National Bank of Umm Al Qaiwain", ar: "بنك أم القيوين الوطني", aliases: ["nbq", "umm al qaiwain", "أم القيوين"], colors: (0x5A1E24, 0xA8424C)),
        .init(id: "almasraf", en: "Al Masraf", ar: "المصرف", aliases: ["al masraf", "almasraf", "arab bank for investment"], colors: (0x0B4B6E, 0x2E8FB8)),
        .init(id: "zand", en: "Zand", ar: "زاند", aliases: ["zand"], colors: (0x101010, 0x8A6BFF)),
        .init(id: "tabby", en: "Tabby", ar: "تابي", aliases: ["tabby"], colors: (0x2E2E2E, 0x3BFFC1)),
        .init(id: "tamara", en: "Tamara", ar: "تمارا", aliases: ["tamara"], colors: (0x2A1B4E, 0xE08A5A)),
        .init(id: "ivestor", en: "iVESTOR", ar: "آيفستر", aliases: ["ivestor", "آيفستر", "dfm ivestor"], colors: (0x5A3A9A, 0x6AA8B8)),
        // Investment and savings apps with no card: faces drawn in each brand's colours.
        .init(id: "thndr", en: "Thndr", ar: "ثندر", aliases: ["thndr", "ثندر"], colors: (0x0A0A0A, 0xFFE500)),
        .init(id: "nbonds", en: "National Bonds", ar: "الصكوك الوطنية", aliases: ["national bonds", "الصكوك الوطنية"], colors: (0x8A6A1E, 0xC9A24A)),
        .init(id: "sarwa", en: "Sarwa", ar: "ثروة", aliases: ["sarwa", "ثروة"], colors: (0x07351A, 0x106E37)),
        .init(id: "baraka", en: "Baraka", ar: "بركة", aliases: ["baraka", "بركة"], colors: (0x000000, 0x3A3A3C))
    ]

    /// The bank named in an account's institution or name. Longest aliases first, whole words for short ones.
    static func match(_ texts: [String?]) -> GhafUAEBank? {
        let text = " " + texts.compactMap { $0?.lowercased() }.joined(separator: " ") + " "
        let candidates = all.flatMap { bank in bank.aliases.map { (bank, $0) } }.sorted { $0.1.count > $1.1.count }
        return candidates.first { _, alias in
            alias.count <= 4 ? text.contains(" \(alias) ") : text.contains(alias)
        }?.0
    }

    var gradient: LinearGradient {
        func color(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        return LinearGradient(colors: [color(colors.0), color(colors.1)], startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

/// An account's card: the real card image when one is chosen, else a face drawn in its bank's colours.
struct GhafCardFace: View {
    let account: GhafAccount?
    var name: String = ""
    var institution: String = ""
    var lastFour: String = ""
    var design: GhafCardDesign? = nil
    var width: CGFloat = 320

    private var bank: GhafUAEBank? { GhafUAEBank.match([institution, name]) }
    private var radius: CGFloat { width * 0.06 }

    var body: some View {
        Group {
            if let design {
                design.image.resizable().aspectRatio(1.586, contentMode: .fill)
            } else {
                drawn
            }
        }
        .frame(width: width, height: width / 1.586)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(width > 100 ? 0.25 : 0), radius: 16, y: 8)
        .accessibilityElement()
        .accessibilityLabel(design?.title ?? bank?.en ?? name)
    }

    private var drawn: some View {
        ZStack(alignment: .topLeading) {
            (bank?.gradient ?? LinearGradient(colors: [Color(white: 0.22), Color(white: 0.42)], startPoint: .bottomLeading, endPoint: .topTrailing))
            // Soft light sweep so the face reads as a physical card.
            LinearGradient(colors: [.white.opacity(0.18), .clear, .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if width > 100 {
                VStack(alignment: .leading) {
                    Text(bank?.en ?? (institution.isEmpty ? name : institution))
                        .font(.system(size: width * 0.055, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    RoundedRectangle(cornerRadius: width * 0.012)
                        .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.76, blue: 0.5), Color(red: 0.66, green: 0.55, blue: 0.32)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: width * 0.13, height: width * 0.1)
                    Spacer()
                    HStack {
                        Text(name.isEmpty ? " " : name).font(.system(size: width * 0.045, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(lastFour.isEmpty ? "•••• ••••" : "•••• \(lastFour)")
                            .font(.system(size: width * 0.045, weight: .semibold, design: .monospaced))
                    }
                }
                .foregroundStyle(.white)
                .padding(width * 0.07)
            }
        }
    }
}

extension GhafCardFace {
    /// A small card for list rows: only for bank accounts with a chosen image or a recognised bank.
    static func mini(for account: GhafAccount, width: CGFloat = 46) -> GhafCardFace? {
        let design = GhafCardDesign.forAccount(account)
        guard design != nil || (account.type.isBankAccount && GhafUAEBank.match([account.institution, account.name]) != nil)
        else { return nil }
        return GhafCardFace(account: account, name: account.name, institution: account.institution ?? "",
                            lastFour: account.lastFourDigits ?? "", design: design, width: width)
    }
}
