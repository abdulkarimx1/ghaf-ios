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
    /// Only populated when the bank publishes a custom URL scheme that can be queried by iOS.
    let urlScheme: String?

    init(id: String, name: String, nameArabic: String, countryName: String, countryNameArabic: String,
         localPhone: String, internationalPhone: String, website: URL, aliases: [String], urlScheme: String? = nil) {
        self.id = id
        self.name = name
        self.nameArabic = nameArabic
        self.countryName = countryName
        self.countryNameArabic = countryNameArabic
        self.localPhone = localPhone
        self.internationalPhone = internationalPhone
        self.website = website
        self.aliases = aliases
        self.urlScheme = urlScheme
    }

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
        ),
        GhafBankSupportContact(
            id: "ajman", name: "Ajman Bank", nameArabic: "مصرف عجمان",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 555 522", internationalPhone: "+971 600 555 522",
            website: URL(string: "https://www.ajmanbank.ae/site/contact-us.html")!,
            aliases: ["ajman bank", "مصرف عجمان"]
        ),
        GhafBankSupportContact(
            id: "alhilal", name: "Al Hilal Bank", nameArabic: "مصرف الهلال",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 522 229", internationalPhone: "+971 600 522 229",
            website: URL(string: "https://www.alhilalbank.ae/en/get-in-touch/call-us.aspx")!,
            aliases: ["al hilal bank", "alhilal", "مصرف الهلال"]
        ),
        GhafBankSupportContact(
            id: "almasraf", name: "Al Masraf", nameArabic: "المصرف",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 52 9999", internationalPhone: "+971 600 52 9999",
            website: URL(string: "https://www.almasraf.ae/contact-us")!,
            aliases: ["al masraf", "almasraf", "المصرف"]
        ),
        GhafBankSupportContact(
            id: "cbd", name: "Commercial Bank of Dubai", nameArabic: "بنك دبي التجاري",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 575 556", internationalPhone: "+971 600 575 556",
            website: URL(string: "https://www.cbd.ae/general/get-in-touch")!,
            aliases: ["commercial bank of dubai", "بنك دبي التجاري"]
        ),
        GhafBankSupportContact(
            id: "cbi", name: "Commercial Bank International", nameArabic: "البنك التجاري الدولي",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 544 440", internationalPhone: "+971 4 503 9000",
            website: URL(string: "https://www.cbiuae.com/en/personal/contact-and-support/")!,
            aliases: ["commercial bank international", "البنك التجاري الدولي"]
        ),
        GhafBankSupportContact(
            id: "hsbcuae", name: "HSBC UAE", nameArabic: "إتش إس بي سي",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 55 4722", internationalPhone: "+971 4 228 8007",
            website: URL(string: "https://www.hsbc.ae/help/contact/")!,
            aliases: ["hsbc", "hsbc uae", "إتش إس بي سي"]
        ),
        GhafBankSupportContact(
            id: "liv", name: "Liv", nameArabic: "ليف",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 521 212", internationalPhone: "+971 600 521 212",
            website: URL(string: "https://www.liv.me/en/ways-of-banking/reach-us")!,
            aliases: ["liv bank"]
        ),
        GhafBankSupportContact(
            id: "nbq", name: "National Bank of Umm Al Qaiwain", nameArabic: "بنك أم القيوين الوطني",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 56 56 56", internationalPhone: "+971 600 56 56 56",
            website: URL(string: "https://www.nbq.ae/general/contact")!,
            aliases: ["national bank of umm al qaiwain", "بنك أم القيوين الوطني"]
        ),
        GhafBankSupportContact(
            id: "scuae", name: "Standard Chartered UAE", nameArabic: "ستاندرد تشارترد",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 5222 88", internationalPhone: "+971 600 5222 88",
            website: URL(string: "https://www.sc.com/ae/contact-us/")!,
            aliases: ["standard chartered", "stanchart", "ستاندرد تشارترد"]
        ),
        GhafBankSupportContact(
            id: "uab", name: "United Arab Bank", nameArabic: "البنك العربي المتحد",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "800 474", internationalPhone: "+971 6 598 7332",
            website: URL(string: "https://www.uab.ae/en/help-center/contact-us")!,
            aliases: ["united arab bank", "البنك العربي المتحد"]
        ),
        GhafBankSupportContact(
            id: "arabbank", name: "Arab Bank", nameArabic: "البنك العربي",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "04 445 0000", internationalPhone: "+971 4 445 0000",
            website: URL(string: "https://www.arabbank.ae/mainmenu/home/ways-to-bank/Customer-Care-Center")!,
            aliases: ["arab bank", "البنك العربي"]
        ),
        GhafBankSupportContact(
            id: "bos", name: "Bank of Sharjah", nameArabic: "بنك الشارقة",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "06 569 4411", internationalPhone: "+971 6 569 4411",
            website: URL(string: "https://www.bankofsharjah.com/en/contactus")!,
            aliases: ["bank of sharjah", "بنك الشارقة"]
        ),
        GhafBankSupportContact(
            id: "zand", name: "Zand", nameArabic: "زاند",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 502 328", internationalPhone: "+971 600 502 328",
            website: URL(string: "https://www.zand.ae/en/contact-us")!,
            aliases: ["zand", "zand bank", "زاند"]
        ),
        GhafBankSupportContact(
            id: "nbf", name: "National Bank of Fujairah", nameArabic: "بنك الفجيرة الوطني",
            countryName: "United Arab Emirates", countryNameArabic: "الإمارات العربية المتحدة",
            localPhone: "600 565 551", internationalPhone: "+971 4 815 7555",
            website: URL(string: "https://nbf.ae/contact/")!,
            aliases: ["national bank of fujairah", "بنك الفجيرة الوطني"]
        ),
        GhafBankSupportContact(
            id: "anb", name: "Arab National Bank", nameArabic: "البنك العربي الوطني",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 124 4040", internationalPhone: "+966 11 212 7555",
            website: URL(string: "https://anb.com.sa/web/anb/contact-us")!,
            aliases: ["arab national bank", "البنك العربي الوطني"]
        ),
        GhafBankSupportContact(
            id: "bsf", name: "Banque Saudi Fransi", nameArabic: "البنك السعودي الفرنسي",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 124 2121", internationalPhone: "+966 92 000 0576",
            website: URL(string: "https://bsf.sa/english/contactus")!,
            aliases: ["banque saudi fransi", "saudi fransi", "البنك السعودي الفرنسي"]
        ),
        GhafBankSupportContact(
            id: "sab", name: "Saudi Awwal Bank", nameArabic: "البنك السعودي الأول",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 124 8888", internationalPhone: "+966 11 406 2800",
            website: URL(string: "https://www.sab.com/en/personal/help-and-support/contact-us/")!,
            aliases: ["saudi awwal", "saudi british bank", "alawwal", "البنك السعودي الأول"]
        ),
        GhafBankSupportContact(
            id: "saib", name: "Saudi Investment Bank", nameArabic: "البنك السعودي للاستثمار",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "011 477 8433", internationalPhone: "+966 11 477 8433",
            website: URL(string: "https://www.saib.com.sa/en/contact-us-0")!,
            aliases: ["saib", "saudi investment bank", "البنك السعودي للاستثمار"]
        ),
        GhafBankSupportContact(
            id: "visionbank", name: "Vision Bank", nameArabic: "بنك فيجن",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 100 0010", internationalPhone: "+966 11 512 7999",
            website: URL(string: "https://www.visionbank.com.sa/contact")!,
            aliases: ["vision bank", "visionbank", "بنك فيجن"]
        ),
        GhafBankSupportContact(
            id: "d360", name: "D360 Bank", nameArabic: "بنك D360",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 124 4410", internationalPhone: "+966 92 002 4360",
            website: URL(string: "https://d360.com/en/contact-us")!,
            aliases: ["d360", "d360 bank", "بنك d360"]
        ),
        GhafBankSupportContact(
            id: "meem", name: "meem", nameArabic: "ميم",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 116 6336", internationalPhone: "+966 92 002 6336",
            website: URL(string: "https://meem.com.sa/")!,
            aliases: ["meem", "gulf international bank saudi arabia"]
        ),
        GhafBankSupportContact(
            id: "aljazira", name: "Bank AlJazira", nameArabic: "بنك الجزيرة",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 244 0404", internationalPhone: "+966 92 000 6666",
            website: URL(string: "https://www.aljazirabank.com.sa/en-us/bank/contactus")!,
            aliases: ["bank aljazira", "aljazira", "al jazira", "بنك الجزيرة"]
        ),
        GhafBankSupportContact(
            id: "stcbank", name: "STC Bank", nameArabic: "بنك stc",
            countryName: "Saudi Arabia", countryNameArabic: "المملكة العربية السعودية",
            localPhone: "800 118 0008", internationalPhone: "+966 92 001 1444",
            website: URL(string: "https://stcbank.com.sa")!,
            aliases: ["stc bank", "stcbank", "بنك stc"]
        ),
        GhafBankSupportContact(
            id: "burgan", name: "Burgan Bank", nameArabic: "بنك برقان",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "1804080", internationalPhone: "+965 1804080",
            website: URL(string: "https://burgan.com/en/services/contact-us/")!,
            aliases: ["burgan bank", "burgan", "بنك برقان"]
        ),
        GhafBankSupportContact(
            id: "gulfbank", name: "Gulf Bank", nameArabic: "بنك الخليج",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "1805805", internationalPhone: "+965 2244 4383",
            website: URL(string: "https://www.e-gulfbank.com/en/contact-us/")!,
            aliases: ["gulf bank", "gulfbank", "بنك الخليج"]
        ),
        GhafBankSupportContact(
            id: "abk", name: "Al Ahli Bank of Kuwait", nameArabic: "البنك الأهلي الكويتي",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "1899899", internationalPhone: "+965 2290 7222",
            website: URL(string: "https://abk.eahli.com/en/contact/contact-us/")!,
            aliases: ["al ahli bank of kuwait", "ahli bank kuwait", "البنك الأهلي الكويتي"]
        ),
        GhafBankSupportContact(
            id: "cbk", name: "Commercial Bank of Kuwait", nameArabic: "البنك التجاري الكويتي",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "1888225", internationalPhone: "+965 1888225",
            website: URL(string: "https://www.cbk.com")!,
            aliases: ["commercial bank of kuwait", "البنك التجاري الكويتي"]
        ),
        GhafBankSupportContact(
            id: "warba", name: "Warba Bank", nameArabic: "بنك وربة",
            countryName: "Kuwait", countryNameArabic: "الكويت",
            localPhone: "182 5555", internationalPhone: "+965 182 5555",
            website: URL(string: "https://www.warbabank.com")!,
            aliases: ["warba bank", "warba", "بنك وربة"]
        ),
        GhafBankSupportContact(
            id: "cbq", name: "Commercial Bank of Qatar", nameArabic: "البنك التجاري",
            countryName: "Qatar", countryNameArabic: "قطر",
            localPhone: "4449 0000", internationalPhone: "+974 4449 0000",
            website: URL(string: "https://www.cbq.com.qa/en/about-us/contact-us")!,
            aliases: ["commercial bank of qatar", "البنك التجاري القطري"]
        ),
        GhafBankSupportContact(
            id: "dukhan", name: "Dukhan Bank", nameArabic: "بنك دخان",
            countryName: "Qatar", countryNameArabic: "قطر",
            localPhone: "800 8555", internationalPhone: "+974 4410 0888",
            website: URL(string: "https://www.dukhanbank.com/contact-us")!,
            aliases: ["dukhan bank", "dukhan", "بنك دخان"]
        ),
        GhafBankSupportContact(
            id: "qiib", name: "Qatar International Islamic Bank", nameArabic: "بنك قطر الدولي الإسلامي",
            countryName: "Qatar", countryNameArabic: "قطر",
            localPhone: "4484 0000", internationalPhone: "+974 4484 0000",
            website: URL(string: "https://www.qiib.com.qa")!,
            aliases: ["qiib", "qatar international islamic bank", "بنك قطر الدولي الإسلامي"]
        ),
        GhafBankSupportContact(
            id: "alrayan", name: "Masraf Al Rayan", nameArabic: "مصرف الريان",
            countryName: "Qatar", countryNameArabic: "قطر",
            localPhone: "4425 3333", internationalPhone: "+974 4425 3333",
            website: URL(string: "https://www.alrayan.com/en/contact-us")!,
            aliases: ["al rayan", "alrayan", "masraf al rayan", "بنك الريان", "مصرف الريان"]
        ),
        GhafBankSupportContact(
            id: "ahliqatar", name: "Ahli Bank Qatar", nameArabic: "البنك الأهلي القطري",
            countryName: "Qatar", countryNameArabic: "قطر",
            localPhone: "4420 5222", internationalPhone: "+974 4420 5222",
            website: URL(string: "https://www.ahlibank.com.qa/en/Others/Contact-Us")!,
            aliases: ["ahli bank qatar", "ahlibank qatar", "البنك الأهلي القطري"]
        ),
        GhafBankSupportContact(
            id: "alsalam", name: "Al Salam Bank", nameArabic: "بنك السلام",
            countryName: "Bahrain", countryNameArabic: "البحرين",
            localPhone: "1700 5500", internationalPhone: "+973 1700 5500",
            website: URL(string: "https://www.alsalambank.com/contact-us/")!,
            aliases: ["al salam bank", "alsalam bank", "بنك السلام"]
        ),
        GhafBankSupportContact(
            id: "bankabc", name: "ila Bank", nameArabic: "بنك إلى",
            countryName: "Bahrain", countryNameArabic: "البحرين",
            localPhone: "1712 3456", internationalPhone: "+973 1712 3456",
            website: URL(string: "https://www.ilabank.com")!,
            aliases: ["ila bank", "ilabank", "bank abc", "abc bank", "بنك إلى"]
        ),
        GhafBankSupportContact(
            id: "bisb", name: "Bahrain Islamic Bank", nameArabic: "بنك البحرين الإسلامي",
            countryName: "Bahrain", countryNameArabic: "البحرين",
            localPhone: "1751 5151", internationalPhone: "+973 1751 5151",
            website: URL(string: "https://www.bisb.com/en/reach-us")!,
            aliases: ["bisb", "bahrain islamic bank", "بنك البحرين الإسلامي"]
        ),
        GhafBankSupportContact(
            id: "khaleeji", name: "Khaleeji Bank", nameArabic: "بنك الخليجي",
            countryName: "Bahrain", countryNameArabic: "البحرين",
            localPhone: "1754 0054", internationalPhone: "+973 1754 0054",
            website: URL(string: "https://khaleeji.bank/")!,
            aliases: ["khaleeji bank", "khaleeji", "بنك الخليجي"]
        ),
        GhafBankSupportContact(
            id: "nizwa", name: "Bank Nizwa", nameArabic: "بنك نزوى",
            countryName: "Oman", countryNameArabic: "سلطنة عُمان",
            localPhone: "2495 0500", internationalPhone: "+968 2495 0500",
            website: URL(string: "https://www.banknizwa.om/en/contact-us")!,
            aliases: ["bank nizwa", "nizwa", "بنك نزوى"]
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
