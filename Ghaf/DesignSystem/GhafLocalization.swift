import Foundation

enum GhafLocalization {
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
            "Salary": "الراتب",
            "Other": "أخرى"
        ]
        return translations[value] ?? value
    }
}