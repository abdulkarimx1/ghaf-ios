import Foundation
import SwiftData
import GhafCore

@MainActor
enum MerchantCategorizer {

    private static let seededRules: [(String, String)] = [

        // Groceries — English and Arabic merchant names
        ("carrefour", "Groceries"),
        ("كارفور", "Groceries"),
        ("lulu", "Groceries"),
        ("لولو", "Groceries"),
        ("nesto", "Groceries"),
        ("نستو", "Groceries"),
        ("spinneys", "Groceries"),
        ("سبينيس", "Groceries"),
        ("union coop", "Groceries"),
        ("جمعية الاتحاد", "Groceries"),
        ("التعاونية", "Groceries"),
        ("جمعية الشارقة التعاونية", "Groceries"),
        
        // Spoken purchase descriptions
        ("grocery", "Groceries"),
        ("groceries", "Groceries"),
        ("supermarket", "Groceries"),
        ("food shop", "Groceries"),
        ("بقالة", "Groceries"),
        ("مواد غذائية", "Groceries"),
        ("تموينات", "Groceries"),

        ("medicine", "Health"),
        ("medication", "Health"),
        ("meds", "Health"),
        ("pharmacy", "Health"),
        ("صيدلية", "Health"),
        ("أدوية", "Health"),
        ("دواء", "Health"),

        ("petrol", "Fuel"),
        ("gas station", "Fuel"),
        ("fuel", "Fuel"),
        ("بنزين", "Fuel"),
        ("وقود", "Fuel"),

        ("taxi", "Transport"),
        ("parking", "Transport"),
        ("metro", "Transport"),
        ("bus", "Transport"),
        ("مواصلات", "Transport"),
        ("موقف", "Transport"),

        ("rent", "Bills & Utilities"),
        ("electricity", "Bills & Utilities"),
        ("water bill", "Bills & Utilities"),
        ("internet bill", "Bills & Utilities"),
        ("إيجار", "Bills & Utilities"),
        ("كهرباء", "Bills & Utilities"),
        ("مياه", "Bills & Utilities"),
        ("إنترنت", "Bills & Utilities"),

        // Dining
        ("talabat", "Dining"),
        ("طلبات", "Dining"),
        ("deliveroo", "Dining"),
        ("ديليفرو", "Dining"),
        ("noon food", "Dining"),
        ("zomato", "Dining"),

        // Transport
        ("careem", "Transport"),
        ("كريم", "Transport"),
        ("uber", "Transport"),
        ("أوبر", "Transport"),
        ("اوبر", "Transport"),
        ("salik", "Transport"),
        ("سالك", "Transport"),
        ("rta", "Transport"),

        // Fuel
        ("adnoc", "Fuel"),
        ("أدنوك", "Fuel"),
        ("ادنوك", "Fuel"),
        ("enoc", "Fuel"),
        ("اينوك", "Fuel"),
        ("eppco", "Fuel"),

        // Utilities
        ("dewa", "Bills & Utilities"),
        ("ديوا", "Bills & Utilities"),
        ("sewa", "Bills & Utilities"),
        ("سيوا", "Bills & Utilities"),
        ("etisalat", "Bills & Utilities"),
        ("اتصالات", "Bills & Utilities"),
        ("eand", "Bills & Utilities"),
        ("du", "Bills & Utilities"),
        ("دو", "Bills & Utilities"),

        // Shopping
        ("noon", "Shopping"),
        ("نون", "Shopping"),
        ("amazon", "Shopping"),
        ("أمازون", "Shopping"),
        ("امازون", "Shopping"),
        ("namshi", "Shopping"),
        ("shein", "Shopping"),
        ("ikea", "Shopping"),

        // Health
        ("life pharmacy", "Health"),
        ("صيدلية لايف", "Health"),
        ("aster pharmacy", "Health"),
        ("استر", "Health"),
        ("أستر", "Health"),
        ("boots", "Health"),

        // Entertainment
        ("netflix", "Entertainment"),
        ("نتفلكس", "Entertainment"),
        ("spotify", "Entertainment"),
        ("سبوتيفاي", "Entertainment"),
        ("apple services", "Entertainment"),

        // Travel
        ("emirates airlines", "Travel"),
        ("طيران الإمارات", "Travel"),
        ("طيران الامارات", "Travel"),
        ("etihad airways", "Travel"),
        ("الاتحاد للطيران", "Travel"),
        ("air arabia", "Travel"),
        ("العربية للطيران", "Travel"),
        ("booking.com", "Travel"),
        ("mcdonalds", "Dining"),
        ("ماكدونالدز", "Dining"),
        ("starbucks", "Dining"),
        ("ستاربكس", "Dining"),
        ("shake shack", "Dining"),
        ("شيك شاك", "Dining")
    ]

    static func normalize(_ merchant: String) -> String {

        return merchant
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US")
            )
            .lowercased()
            .split(whereSeparator: {
                !$0.isLetter && !$0.isNumber
            })
            .joined(separator: " ")
    }

    static func category(
        for merchant: String?,
        direction: TransactionDirection,
        context: ModelContext
    ) throws -> String {

        guard let merchant else {

            return direction == .credit
                ? "Transfers"
                : "Other"
        }

        let key = normalize(merchant)

        // User-defined rules take priority.
        let descriptor = FetchDescriptor<MerchantCategoryRule>(
            predicate: #Predicate {
                $0.normalizedMerchant == key
            }
        )

        if let learnedRule = try context.fetch(descriptor).first {
            return learnedRule.category
        }

        // Use built-in UAE merchant rules.
        // Match complete normalized words/phrases. Unbounded substring
        // matching caused short rules such as "du" to match unrelated names.
        let paddedKey = " \(key) "
        for (merchantName, category) in seededRules {
            let rule = normalize(merchantName)
            guard !rule.isEmpty else { continue }
            if paddedKey.contains(" \(rule) ") {
                return category
            }
        }

        if key.contains("salary") {
            return "Salary"
        }

        return direction == .credit
            ? "Transfers"
            : "Other"
    }

    /// Saves a user's category correction.
    static func learn(
        merchant: String,
        category: String,
        context: ModelContext,
        saveImmediately: Bool = true
    ) throws {

        let key = normalize(merchant)

        guard !key.isEmpty else {
            return
        }

        let descriptor = FetchDescriptor<MerchantCategoryRule>(
            predicate: #Predicate {
                $0.normalizedMerchant == key
            }
        )

        if let existing = try context.fetch(descriptor).first {

            existing.category = category
            existing.updatedAt = Date()

        } else {

            let rule = MerchantCategoryRule(
                normalizedMerchant: key,
                category: category
            )

            context.insert(rule)
        }

        if saveImmediately {
            try context.save()
        }
    }
}
