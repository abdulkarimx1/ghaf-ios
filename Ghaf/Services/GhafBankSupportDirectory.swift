import Foundation

struct GhafBankSupportContact: Identifiable {
    let id: String
    let name: String
    let nameArabic: String
    let localPhone: String
    let internationalPhone: String
    let website: URL
    let aliases: [String]

    var localDialString: String {
        localPhone.filter { $0.isNumber || $0 == "+" }
    }

    var internationalDialString: String {
        internationalPhone.filter { $0.isNumber || $0 == "+" }
    }
}

enum GhafBankSupportDirectory {
    // UAE contacts verified against each institution's official support page.
    // Add new institutions only after verifying the current official number.
    static let contacts: [GhafBankSupportContact] = [
        GhafBankSupportContact(
            id: "mashreq",
            name: "Mashreq",
            nameArabic: "المشرق",
            localPhone: "04 424 4444",
            internationalPhone: "+971 4 424 4444",
            website: URL(string: "https://www.mashreq.com/uae/customer-care/contact-us/")!,
            aliases: ["mashreq", "mashreq neo", "mashreq bank"]
        ),
        GhafBankSupportContact(
            id: "mbank",
            name: "Mbank UAE",
            nameArabic: "مصرف الإمارات للتنمية المجتمعية",
            localPhone: "600 57 1111",
            internationalPhone: "+971 2 412 2222",
            website: URL(string: "https://www.mbank.ae/contact-us/")!,
            aliases: ["mbank", "m bank", "al maryah community bank", "amcb"]
        ),
        GhafBankSupportContact(
            id: "ruya",
            name: "ruya",
            nameArabic: "رُويا",
            localPhone: "600 507 892",
            internationalPhone: "+971 6 707 0570",
            website: URL(string: "https://ruyabank.ae/en/contact-us")!,
            aliases: ["ruya", "ruya bank", "ruya community islamic bank"]
        ),
        GhafBankSupportContact(
            id: "ivestor",
            name: "iVestor",
            nameArabic: "آي فيستور",
            localPhone: "04 305 5555",
            internationalPhone: "+971 4 305 5555",
            website: URL(string: "https://ivestor.ae/support/")!,
            aliases: ["ivestor", "dfm", "dubai financial market"]
        )
    ]

    static func contact(for identifiers: [String?]) -> GhafBankSupportContact? {
        let values = identifiers.compactMap { $0 }
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }

        for contact in contacts {
            let aliases = contact.aliases.map(normalize)
            if values.contains(where: { value in
                aliases.contains(where: { alias in
                    value == alias || value.contains(alias) || alias.contains(value)
                })
            }) {
                return contact
            }
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}
