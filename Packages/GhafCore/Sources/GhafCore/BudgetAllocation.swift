import Foundation

/// The 50/30/20 split behind the Budget card: half of income for needs, 30% for wants, 20% saved.
/// Which bucket a category falls in is a fixed rule over the built-in taxonomy, so the split is
/// deterministic and explainable; anything not recognised as a need counts as a want.
public enum BudgetAllocation {
    public enum Bucket: Int, CaseIterable, Sendable { case needs, wants, savings }

    public enum Preset: String, CaseIterable, Sendable {
        case balanced, highRentCity, saver

        public var shares: [Bucket: Decimal] {
            switch self {
            case .balanced: [.needs: 0.5, .wants: 0.3, .savings: 0.2]
            case .highRentCity: [.needs: 0.6, .wants: 0.2, .savings: 0.2]
            case .saver: [.needs: 0.6, .wants: 0.1, .savings: 0.3]
            }
        }

        public var title: String {
            switch self { case .balanced: "50/30/20"; case .highRentCity: "60/20/20"; case .saver: "60/10/30" }
        }

        public var description: String {
            switch self {
            case .balanced: "For fixed costs under half your pay"
            case .highRentCity: "When rent and bills take 55% or more"
            case .saver: "For a savings goal like a home deposit"
            }
        }

        public func share(_ bucket: Bucket) -> Decimal { shares[bucket] ?? 0 }

        public func amount(for bucket: Bucket, income: Decimal) -> Decimal { income * share(bucket) }
    }

    public static func share(_ bucket: Bucket) -> Decimal {
        Preset.balanced.share(bucket)
    }

    /// Built-in categories that are essentials.
    static let needCategories: Set<String> = ["Groceries", "Car & Transport", "Housing", "Bills & Utilities",
                                              "Health & Wellness", "Education", "Family & Kids",
                                              "Government & Documents", "Financial"]

    /// Needs for a built-in category, its alias ("Car", "Utilities"), or one of its subcategories or
    /// words ("Fuel", "Home rent"); wants otherwise.
    public static func bucket(forCategory name: String) -> Bucket {
        if let category = CategoryTaxonomy.category(named: name) {
            return needCategories.contains(category.name) ? .needs : .wants
        }
        let key = CategoryMatcher.normalize(name)
        let isNeed = CategoryTaxonomy.all.contains { category in
            needCategories.contains(category.name) && category.subcategories.contains { sub in
                CategoryMatcher.normalize(sub.name) == key || sub.words.map(CategoryMatcher.normalize).contains(key)
            }
        }
        return isNeed ? .needs : .wants
    }
}
