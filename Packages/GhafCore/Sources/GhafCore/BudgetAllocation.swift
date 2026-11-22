import Foundation

/// The 50/30/20 split behind the Budget card: half of income for needs, 30% for wants, 20% saved.
/// Which bucket a category falls in is a fixed rule over the built-in taxonomy, so the split is
/// deterministic and explainable; anything not recognised as a need counts as a want.
public enum BudgetAllocation {
    public struct PetalRadii: Equatable, Sendable {
        public let outer: Double
        public let fill: Double
    }

    /// Keeps every budget petal at the same outer radius and grows the spend inward from its edge.
    public static func petalRadii(budget: Decimal, spent: Decimal, innerRadius: Double, fillLimit: Double = 0.8) -> PetalRadii {
        let inner = min(max(innerRadius, 0), 1)
        let limit = min(max(fillLimit, inner), 1)
        guard budget > 0, spent > 0 else { return PetalRadii(outer: 1, fill: inner) }
        let spentRatio = min(1, NSDecimalNumber(decimal: spent / budget).doubleValue)
        return PetalRadii(outer: 1, fill: inner + (limit - inner) * spentRatio)
    }

    /// Income not spent in the Needs and Wants buckets; this is a budget estimate, not a bank balance.
    public static func remainingAfterSpending(income: Decimal, needs: Decimal, wants: Decimal) -> Decimal {
        income - needs - wants
    }

    public static func savingsGoalReached(remaining: Decimal, goal: Decimal) -> Bool {
        goal > 0 && remaining >= goal
    }

    public enum Bucket: Int, CaseIterable, Sendable { case needs, wants, savings }

    public enum Preset: String, CaseIterable, Sendable {
        case balanced, highRentCity, essentialsFirst
        case guardian

        public var shares: [Bucket: Decimal] {
            switch self {
            case .balanced: [.needs: 0.5, .wants: 0.3, .savings: 0.2]
            case .highRentCity: [.needs: 0.6, .wants: 0.2, .savings: 0.2]
            case .essentialsFirst: [.needs: 0.6, .wants: 0.3, .savings: 0.1]
            case .guardian: [.needs: 0.7, .wants: 0.2, .savings: 0.1]
            }
        }

        public var title: String {
            switch self {
            case .balanced: "50/30/20"
            case .highRentCity: "60/20/20"
            case .essentialsFirst: "60/30/10"
            case .guardian: "70/20/10"
            }
        }

        public var name: String {
            switch self {
            case .balanced: "The Hero"
            case .highRentCity: "The Strategist"
            case .essentialsFirst: "The Explorer"
            case .guardian: "The Guardian"
            }
        }

        public var description: String {
            switch self {
            case .balanced: "For fixed costs under half your pay"
            case .highRentCity: "When rent and bills take 55% or more"
            case .essentialsFirst: "When bills are high and savings start small"
            case .guardian: "When essentials need most of your income"
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
