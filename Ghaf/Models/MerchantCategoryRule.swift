import Foundation
import SwiftData

@Model
final class MerchantCategoryRule {

    @Attribute(.unique)
    var normalizedMerchant: String

    var category: String

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
