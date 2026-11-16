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
        CategoryMatcher.normalize(merchant)
    }

    // MARK: Learned model

    /// Trained from confirmed transactions, one model per direction; rebuilt after a correction or new data.
    private static var learners: [String: (count: Int, model: CategoryLearner)] = [:]

    static func invalidateLearner() { learners = [:] }

    /// UserDefaults switch (More › What Ghaf learned); on by default.
    static let modelLearningKey = "ghaf.ai.modelLearning"

    private static func learner(direction: TransactionDirection, context: ModelContext) -> CategoryLearner? {
        guard UserDefaults.standard.object(forKey: modelLearningKey) as? Bool ?? true else { return nil }
        let raw = direction.rawValue
        let count = (try? context.fetchCount(FetchDescriptor<GhafTransaction>())) ?? 0
        if let cached = learners[raw], cached.count == count { return cached.model }
        let confirmed = (try? context.fetch(FetchDescriptor<GhafTransaction>(
            predicate: #Predicate { !$0.needsReview && !$0.isReversal && $0.direction == raw && $0.merchant != nil }
        ))) ?? []
        let samples = confirmed.compactMap { item -> CategoryLearner.Sample? in
            guard item.isSpendingOrIncome, item.category != "Other", item.category != "Other Income",
                  let merchant = item.merchant else { return nil }
            return .init(merchant: merchant, amount: item.amount, date: item.date, category: item.category, subcategory: item.subcategory)
        }
        let model = CategoryLearner(samples: samples)
        learners[raw] = (count, model)
        return model
    }

    /// Best category and subcategory for a merchant or spoken description, or nil when nothing fits.
    /// Rules and names come first; the learned model only fills in when they find nothing.
    static func suggestion(for merchant: String?, amount: Decimal = 0, date: Date = .now,
                           direction: TransactionDirection = .debit, context: ModelContext) -> CategoryMatcher.Match? {
        if let match = ruleSuggestion(for: merchant, context: context) { return match }
        guard let merchant, !merchant.isEmpty else { return nil }
        return learner(direction: direction, context: context)?.match(merchant: merchant, amount: amount, date: date)
    }

    private static func ruleSuggestion(for merchant: String?, context: ModelContext) -> CategoryMatcher.Match? {
        guard let merchant, !merchant.isEmpty else { return nil }
        let catalog = (try? context.fetch(FetchDescriptor<GhafSettings>()).first)?.catalog
            ?? Dictionary(uniqueKeysWithValues: GhafDefaults.defaultCategories.map { ($0, [String]()) })
        var learned: [String: CategoryMatcher.Rule] = [:]
        // Built-in UAE merchants first, so the user's own rules overwrite them.
        for (name, category) in seededRules where catalog[category] != nil {
            learned[normalize(name)] = CategoryMatcher.Rule(category: category, subcategory: nil, hits: 0)
        }
        for rule in (try? context.fetch(FetchDescriptor<MerchantCategoryRule>())) ?? [] where catalog[rule.category] != nil {
            learned[rule.normalizedMerchant] = CategoryMatcher.Rule(category: rule.category, subcategory: rule.subcategory, hits: rule.hits)
        }
        return CategoryMatcher.match(merchant, catalog: catalog, learned: learned)
    }

    static func category(
        for merchant: String?,
        direction: TransactionDirection,
        amount: Decimal = 0,
        date: Date = .now,
        context: ModelContext
    ) throws -> String {
        if let match = suggestion(for: merchant, amount: amount, date: date, direction: direction, context: context),
           !match.isNewCategory { return match.category }
        if merchant.map(normalize)?.contains("salary") == true { return "Salary" }
        return direction == .credit ? "Other Income" : "Other"
    }

    /// Saves a confirmed category (and subcategory) for a merchant; repeated confirmations raise its weight.
    static func learn(
        merchant: String,
        category: String,
        subcategory: String? = nil,
        context: ModelContext,
        saveImmediately: Bool = true
    ) throws {
        invalidateLearner()
        let key = normalize(merchant)
        guard !key.isEmpty, category != "Other" else { return }

        let descriptor = FetchDescriptor<MerchantCategoryRule>(predicate: #Predicate { $0.normalizedMerchant == key })
        if let existing = try context.fetch(descriptor).first {
            existing.hits = existing.category == category && existing.subcategory == subcategory ? existing.hits + 1 : 1
            existing.category = category
            existing.subcategory = subcategory
            existing.updatedAt = Date()
        } else {
            let rule = MerchantCategoryRule(normalizedMerchant: key, category: category)
            rule.subcategory = subcategory
            context.insert(rule)
        }
        if saveImmediately { try context.save() }
    }
}
