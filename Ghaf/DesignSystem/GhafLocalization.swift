import Foundation
import GhafCore

enum GhafLocalization {
    /// "n days" in Arabic: the counted noun follows the number (٧ أيام، ٣٠ يومًا، ١٠٠ يوم).
    static func arabicDays(_ n: Int) -> String {
        let r = n % 100
        if n == 1 { return "يوم واحد" }
        if n == 2 { return "يومان" }
        if (3...10).contains(r) { return "\(n) أيام" }
        if r == 0 { return "\(n) يوم" }
        return "\(n) يومًا"
    }

#if DEBUG
    static func assertArabicDays() {
        assert(arabicDays(7) == "7 أيام" && arabicDays(30) == "30 يومًا" && arabicDays(100) == "100 يوم" && arabicDays(365) == "365 يومًا")
    }
#endif

    static func count(_ value: Int, singular: String, dual: String, plural: String, afterTen: String, languageCode: String) -> String {
        guard languageCode == "ar" else {
            return "\(value) " + (value == 1 ? singular : plural)
        }
        if value == 0 { return "لا " + plural }
        if value == 1 { return singular }
        if value == 2 { return dual }
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "ar_AE")
        numberFormatter.numberStyle = .decimal
        let formatted = numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
        if (3...10).contains(value) { return "\(formatted) " + plural }
        return "\(formatted) " + afterTen
    }

    static func category(_ value: String, languageCode: String) -> String {
        let isArabic = languageCode.lowercased().hasPrefix("ar")
        if value.caseInsensitiveCompare("Income") == .orderedSame { return isArabic ? "الدخل" : "Income" }
        let englishLabels: [String: String] = [
            "Food & Dining": "Food", "Car & Transport": "Car", "Bills & Utilities": "Bills",
            "Health & Wellness": "Health", "Sports & Fitness": "Fitness", "Housing": "Home",
            "Government & Documents": "Government", "Other Income": "Other income",
            "Freelance & Business": "Freelance", "Rental income": "Rent received", "Profits & Dividends": "Investment returns",
            "Remittance & Exchange": "Remittance", "Furniture & Home": "Furniture",
            "Clinic & Checkups": "Clinic", "Pharmacy & Meds": "Pharmacy",
            "Cafés & Karak": "Cafés", "Bakery & Sweets": "Bakery & sweets"
        ]
        if !isArabic {
            if let category = CategoryTaxonomy.category(named: value) { return englishLabels[category.name] ?? category.name }
            if let subcategory = CategoryTaxonomy.all.lazy.compactMap({ category in
                category.subcategories.first(where: { $0.name == value }).map { (category, $0) }
            }).first { return englishLabels[subcategory.1.name] ?? subcategory.1.name }
            if let transfer = CategoryTaxonomy.transferSubcategories.first(where: { $0.name == value }) { return transfer.name }
            return englishLabels[value] ?? value
        }
        let translations: [String: String] = [
            "Freelance & Business": "عمل حر",
            "Rental income": "دخل إيجار",
            "Groceries": "البقالة",
            "Dining": "الطعام",
            "Food & Dining": "الطعام",
            "Transport": "السيارة",
            "Car & Transport": "السيارة",
            "Housing": "المنزل",
            "Bills & Utilities": "الفواتير",
            "Health & Wellness": "الصحة",
            "Sports & Fitness": "اللياقة",
            "Government & Documents": "الحكومة",
            "Fuel": "الوقود",
            "Shopping": "التسوق",
            "Health": "الصحة",
            "Entertainment": "الترفيه",
            "Travel": "السفر",
            "Transfers": "التحويلات",
            "Adjustment": "تعديل رصيد",
            "Salary": "الراتب",
            "Other": "أخرى",
            "Other Income": "دخل آخر",
            "Subscriptions": "الاشتراكات",
            "Fees": "الرسوم",
            "Debt Repayment": "سداد الديون",
            "Borrowed Money": "أموال مقترضة",
            "Lent Money": "أموال مُقرضة",
            "Interest": "الفوائد"
        ]
        if let direct = translations[value] { return direct }
        if let category = CategoryTaxonomy.category(named: value) { return translations[category.name] ?? category.arabic }
        if let subcategory = CategoryTaxonomy.all.lazy.compactMap({ category in
            category.subcategories.first(where: { $0.name == value }).map { $0.arabic }
        }).first { return subcategory }
        if let transfer = CategoryTaxonomy.transferSubcategories.first(where: { $0.name == value }) { return transfer.arabic }
        return CategoryTaxonomy.arabicName(for: value) ?? value
    }
}
