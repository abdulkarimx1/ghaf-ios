import Foundation
import SwiftData
import GhafCore

@MainActor
enum MerchantCategorizer {

    private static let seededRules: [(String, String)] = [

        // Groceries
        ("carrefour", "Groceries"),
        ("lulu", "Groceries"),
        ("union coop", "Groceries"),
        ("nesto", "Groceries"),
        ("spinneys", "Groceries"),

        // Dining
        ("talabat", "Dining"),
        ("deliveroo", "Dining"),
        ("noon food", "Dining"),
        ("zomato", "Dining"),

        // Transport
        ("careem", "Transport"),
        ("uber", "Transport"),
        ("salik", "Transport"),
        ("rta", "Transport"),

        // Fuel
        ("adnoc", "Fuel"),
        ("enoc", "Fuel"),
        ("eppco", "Fuel"),

        // Utilities
        ("dewa", "Bills & Utilities"),
        ("sewa", "Bills & Utilities"),
        ("etisalat", "Bills & Utilities"),
        ("eand", "Bills & Utilities"),
        ("du", "Bills & Utilities"),

        // Shopping
        ("noon", "Shopping"),
        ("amazon", "Shopping"),
        ("namshi", "Shopping"),
        ("shein", "Shopping"),
        ("ikea", "Shopping"),

        // Health
        ("life pharmacy", "Health"),
        ("aster pharmacy", "Health"),
        ("boots", "Health"),

        // Entertainment
        ("netflix", "Entertainment"),
        ("spotify", "Entertainment"),
        ("apple services", "Entertainment"),

        // Travel
        ("emirates airlines", "Travel"),
        ("etihad airways", "Travel"),
        ("air arabia", "Travel"),
        ("booking.com", "Travel")
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
        for (merchantName, category) in seededRules {

            if key.contains(normalize(merchantName)) {
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
        context: ModelContext
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

        try context.save()
    }
}
