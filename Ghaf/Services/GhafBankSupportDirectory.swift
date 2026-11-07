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
    // GCC contacts verified against each institution's official support page.
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
            aliases: ["mashreq", "mashreq neo", "mashreq bank", "المشرق"]
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
            aliases: ["mbank", "m bank", "al maryah community bank", "amcb", "مصرف الإمارات للتنمية المجتمعية"]
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
            aliases: ["ruya", "ruya bank", "ruya community islamic bank", "رويا"]
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
            aliases: ["ivestor", "dfm", "dubai financial market", "آي فيستور"]
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
        ),
        GhafBankSupportContact(
            id: "emiratesnbd", name: "Emirates NBD", nameArabic: "الإمارات دبي الوطني",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 54 0000", internationalPhone: "+971 600 54 0000",
            website: URL(string: "https://www.emiratesnbd.com/en/help-and-support/contact-us")!,
            aliases: ["emirates nbd", "enbd", "emirates bank", "الإمارات دبي الوطني"]
        ),
        GhafBankSupportContact(
            id: "rakbank", name: "RAKBANK", nameArabic: "بنك رأس الخيمة الوطني",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 54 4049", internationalPhone: "+971 600 54 4049",
            website: URL(string: "https://www.rakbank.ae/en/contact-us")!,
            aliases: ["rakbank", "rak bank", "national bank of ras al khaimah", "بنك رأس الخيمة الوطني"]
        ),
        GhafBankSupportContact(
            id: "fab", name: "First Abu Dhabi Bank", nameArabic: "بنك أبوظبي الأول",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 52 5500", internationalPhone: "+971 2 681 1511",
            website: URL(string: "https://www.bankfab.com/en-ae/contact-us")!,
            aliases: ["fab", "first abu dhabi bank", "بنك أبوظبي الأول"]
        ),
        GhafBankSupportContact(
            id: "adcb", name: "ADCB", nameArabic: "بنك أبوظبي التجاري",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 50 2030", internationalPhone: "+971 600 50 2030",
            website: URL(string: "https://www.adcb.com/en/get-in-touch/call-us/")!,
            aliases: ["adcb", "abu dhabi commercial bank", "بنك أبوظبي التجاري"]
        ),
        GhafBankSupportContact(
            id: "adib", name: "Abu Dhabi Islamic Bank", nameArabic: "مصرف أبوظبي الإسلامي",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 54 3220", internationalPhone: "+971 2 657 8777",
            website: URL(string: "https://www.adib.ae/en/pages/contact-us")!,
            aliases: ["adib", "abu dhabi islamic bank", "مصرف أبوظبي الإسلامي"]
        ),
        GhafBankSupportContact(
            id: "alinma", name: "Alinma Bank", nameArabic: "مصرف الإنماء",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "920 028 000", internationalPhone: "+966 920 028 000",
            website: URL(string: "https://www.alinma.com/en/contact-us")!,
            aliases: ["alinma", "alinma bank", "مصرف الإنماء"]
        ),
        GhafBankSupportContact(
            id: "albilad", name: "Bank Albilad", nameArabic: "بنك البلاد",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 123 0000", internationalPhone: "+966 920 001 002",
            website: URL(string: "https://www.bankalbilad.com.sa/en/Pages/babc.aspx")!,
            aliases: ["bank albilad", "albilad", "بنك البلاد"]
        ),
        GhafBankSupportContact(
            id: "kfh", name: "Kuwait Finance House", nameArabic: "بيت التمويل الكويتي",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "1803333", internationalPhone: "+965 1803333",
            website: URL(string: "https://www.kfh.com/home/Personal/faq/question-form.html")!,
            aliases: ["kfh", "kuwait finance house", "بيت التمويل الكويتي"]
        ),
        GhafBankSupportContact(
            id: "boubyan", name: "Boubyan Bank", nameArabic: "بنك بوبيان",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "1820082", internationalPhone: "+965 22282000",
            website: URL(string: "https://www.bankboubyan.com/en/contact-us")!,
            aliases: ["boubyan", "boubyan bank", "بنك بوبيان"]
        ),
        GhafBankSupportContact(
            id: "bbk", name: "BBK", nameArabic: "بنك البحرين والكويت",
            countryName: "Bahrain", countryNameArabic: "البحرين",
            localPhone: "1720 7777", internationalPhone: "+973 1720 7777",
            website: URL(string: "https://www.bbkonline.com/customer-care/")!,
            aliases: ["bbk", "bank of bahrain and kuwait", "بنك البحرين والكويت"]
        ),
        GhafBankSupportContact(
            id: "sohar", name: "Sohar International", nameArabic: "صحار الدولي",
            countryName: "Oman", countryNameArabic: "سلطنة عُمان",
            localPhone: "800 74666", internationalPhone: "+968 2473 0000",
            website: URL(string: "https://www.sib.om/en/contact-us")!,
            aliases: ["sohar international", "sohar", "صحار الدولي"]
        ),
        GhafBankSupportContact(
            id: "nbo", name: "National Bank of Oman", nameArabic: "البنك الوطني العماني",
            countryName: "Oman", countryNameArabic: "سلطنة عُمان",
            localPhone: "2477 0000", internationalPhone: "+968 2477 0000",
            website: URL(string: "https://www.nbo.om/en/Pages/SME-Banking/Support/Call-Centre-and-IVR.aspx")!,
            aliases: ["national bank of oman", "nbo", "البنك الوطني العماني"]
        ),
        GhafBankSupportContact(
            id: "bankdhofar", name: "BankDhofar", nameArabic: "بنك ظفار",
            countryName: "Oman", countryNameArabic: "سلطنة عُمان",
            localPhone: "2479 1111", internationalPhone: "+968 2479 1111",
            website: URL(string: "https://www.bankdhofar.com/electronic-channels/mobile-banking-new/")!,
            aliases: ["bankdhofar", "bank dhofar", "بنك ظفار"]
        ),
        GhafBankSupportContact(
            id: "qib", name: "Qatar Islamic Bank", nameArabic: "مصرف قطر الإسلامي",
            countryName: "Qatar", countryNameArabic: "قطر",
            localPhone: "4444 8444", internationalPhone: "+974 4444 8444",
            website: URL(string: "https://www.qib.com.qa/en/personal/learn-how-to-money/articles-listing/articles/2026/identity-protection-tips")!,
            aliases: ["qib", "qatar islamic bank", "مصرف قطر الإسلامي"]
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
                    value == alias || value.contains(alias)
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
