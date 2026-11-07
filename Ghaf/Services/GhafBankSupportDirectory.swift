import Foundation

struct GhafBankSupportContact: Identifiable {
    let id: String
    let name: String
    let nameArabic: String
    let countryName: String
    let countryNameArabic: String
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
            countryName: "United Arab Emirates",
            countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "04 424 4444",
            internationalPhone: "+971 4 424 4444",
            website: URL(string: "https://www.mashreq.com/uae/customer-care/contact-us/")!,
            aliases: ["mashreq", "mashreq neo", "mashreq bank"]
        ),
        GhafBankSupportContact(
            id: "mbank",
            name: "Mbank UAE",
            nameArabic: "مصرف الإمارات للتنمية المجتمعية",
            countryName: "United Arab Emirates",
            countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 57 1111",
            internationalPhone: "+971 2 412 2222",
            website: URL(string: "https://www.mbank.ae/contact-us/")!,
            aliases: ["mbank", "m bank", "al maryah community bank", "amcb"]
        ),
        GhafBankSupportContact(
            id: "ruya",
            name: "ruya",
            nameArabic: "رُويا",
            countryName: "United Arab Emirates",
            countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 507 892",
            internationalPhone: "+971 6 707 0570",
            website: URL(string: "https://ruyabank.ae/en/contact-us")!,
            aliases: ["ruya", "ruya bank", "ruya community islamic bank"]
        ),
        GhafBankSupportContact(
            id: "ivestor",
            name: "iVestor",
            nameArabic: "آي فيستور",
            countryName: "United Arab Emirates",
            countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "04 305 5555",
            internationalPhone: "+971 4 305 5555",
            website: URL(string: "https://ivestor.ae/support/")!,
            aliases: ["ivestor", "dfm", "dubai financial market"]
        ),
        GhafBankSupportContact(
            id: "alrajhi",
            name: "Al Rajhi Bank",
            nameArabic: "مصرف الراجحي",
            countryName: "Saudi Arabia",
            countryNameArabic: "المملكة العربية السعودية",
            localPhone: "920 003 344",
            internationalPhone: "+966 920 003 344",
            website: URL(string: "https://www.alrajhibank.com.sa/en/about-alrajhi-bank/complaint-request")!,
            aliases: ["al rajhi", "alrajhi", "al rajhi bank", "مصرف الراجحي"]
        ),
        GhafBankSupportContact(
            id: "snb",
            name: "Saudi National Bank",
            nameArabic: "البنك الأهلي السعودي",
            countryName: "Saudi Arabia",
            countryNameArabic: "المملكة العربية السعودية",
            localPhone: "920 001 000",
            internationalPhone: "+966 920 001 000",
            website: URL(string: "https://www.alahli.com/en/pages/about-us/contact-us")!,
            aliases: ["snb", "saudi national bank", "alahli", "al ahli", "البنك الأهلي السعودي"]
        ),
        GhafBankSupportContact(
            id: "riyad",
            name: "Riyad Bank",
            nameArabic: "بنك الرياض",
            countryName: "Saudi Arabia",
            countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 124 2225",
            internationalPhone: "+966 920 002 470",
            website: URL(string: "https://www.riyadbank.com/ar/contact-us")!,
            aliases: ["riyad bank", "riyadbank", "بنك الرياض"]
        ),
        GhafBankSupportContact(
            id: "nbk",
            name: "National Bank of Kuwait",
            nameArabic: "بنك الكويت الوطني",
            countryName: "Kuwait",
            countryNameArabic: "الكويت",
            localPhone: "1801801",
            internationalPhone: "+965 2292 4888",
            website: URL(string: "https://www.nbk.com/kuwait/contact-us.html")!,
            aliases: ["nbk", "national bank of kuwait", "بنك الكويت الوطني"]
        ),
        GhafBankSupportContact(
            id: "qnb",
            name: "QNB",
            nameArabic: "بنك قطر الوطني",
            countryName: "Qatar",
            countryNameArabic: "قطر",
            localPhone: "4440 7777",
            internationalPhone: "+974 4440 7777",
            website: URL(string: "https://www.qnb.com.qa/sites/qnb/qnbqatar/page/en/encustomerfeedbackinquiries.html")!,
            aliases: ["qnb", "qatar national bank", "بنك قطر الوطني"]
        ),
        GhafBankSupportContact(
            id: "dohabank",
            name: "Doha Bank",
            nameArabic: "بنك الدوحة",
            countryName: "Qatar",
            countryNameArabic: "قطر",
            localPhone: "4445 6000",
            internationalPhone: "+974 4445 6000",
            website: URL(string: "https://www.dohabank.com.qa/contact-us/")!,
            aliases: ["doha bank", "dohabank", "بنك الدوحة"]
        ),
        GhafBankSupportContact(
            id: "nbb",
            name: "National Bank of Bahrain",
            nameArabic: "بنك البحرين الوطني",
            countryName: "Bahrain",
            countryNameArabic: "البحرين",
            localPhone: "1721 4433",
            internationalPhone: "+973 1721 4433",
            website: URL(string: "https://nbbonline.com/contact/")!,
            aliases: ["nbb", "national bank of bahrain", "بنك البحرين الوطني"]
        ),
        GhafBankSupportContact(
            id: "bankmuscat",
            name: "Bank Muscat",
            nameArabic: "بنك مسقط",
            countryName: "Oman",
            countryNameArabic: "سلطنة عُمان",
            localPhone: "2479 5555",
            internationalPhone: "+968 2479 5555",
            website: URL(string: "https://www.bankmuscat.com/en/Pages/default.aspx")!,
            aliases: ["bank muscat", "bankmuscat", "بنك مسقط"]
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
