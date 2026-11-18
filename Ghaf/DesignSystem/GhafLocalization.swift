import Foundation
import GhafCore

enum GhafLocalization {
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
        guard languageCode == "ar" else { return value }
        let translations: [String: String] = [
            "Groceries": "البقالة",
            "Dining": "المطاعم",
            "Transport": "المواصلات",
            "Fuel": "الوقود",
            "Bills & Utilities": "الفواتير والخدمات",
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
        return translations[value] ?? CategoryTaxonomy.arabicName(for: value) ?? value
    }
}