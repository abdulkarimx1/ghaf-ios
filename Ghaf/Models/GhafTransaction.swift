import Foundation
import SwiftData
import GhafCore

@Model
final class GhafTransaction {

    @Attribute(.unique)
    var fingerprint: String

    var id: UUID
    var amount: Decimal
    var currency: String
    var merchant: String?
    var date: Date
    var direction: String
    var category: String
    var confidence: Double
    var bank: String?
    var needsReview: Bool
    var isReversal: Bool
    var note: String?
    var createdAt: Date

    init(
        fingerprint: String,
        parsed: ParsedTransaction,
        category: String,
        needsReview: Bool,
        isReversal: Bool
    ) {
        self.fingerprint = fingerprint
        self.id = UUID()
        self.amount = parsed.amount
        self.currency = parsed.currency
        self.merchant = parsed.merchant
        self.date = parsed.date
        self.direction = parsed.direction.rawValue
        self.category = category
        self.confidence = parsed.confidence
        self.bank = parsed.bank
        self.needsReview = needsReview
        self.isReversal = isReversal
        self.note = nil
        self.createdAt = Date()
    }
}
