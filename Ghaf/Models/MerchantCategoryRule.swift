import Foundation
import SwiftData

@Model
final class MerchantCategoryRule {

    @Attribute(.unique)
    var normalizedMerchant: String

    var category: String

    var subcategory: String? = nil

    /// How many confirmed transactions taught this rule.
    var hits: Int = 1

    var updatedAt: Date

    init(
        normalizedMerchant: String,
        category: String
    ) {
        self.normalizedMerchant = normalizedMerchant
        self.category = category
        self.updatedAt = Date()
    }
}
