import Foundation
import SwiftData

enum GhafBillingCycle: String, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly
    var id: String { rawValue }
    func nextDate(after date: Date) -> Date {
        let component: Calendar.Component
        let value: Int
        switch self {
        case .weekly: component = .day; value = 7
        case .monthly: component = .month; value = 1
        case .quarterly: component = .month; value = 3
        case .yearly: component = .year; value = 1
        }
        return Calendar.current.date(byAdding: component, value: value, to: date) ?? date
    }
    func title(language: String) -> String {
        guard language == "ar" else {
            return switch self { case .weekly: "Weekly"; case .monthly: "Monthly"; case .quarterly: "Every 3 months"; case .yearly: "Yearly" }
        }
        return switch self { case .weekly: "أسبوعي"; case .monthly: "شهري"; case .quarterly: "كل ٣ أشهر"; case .yearly: "سنوي" }
    }
}

@Model
final class GhafSubscription {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Decimal
    var currency: String
    var billingCycle: String
    var nextPaymentDate: Date
    var category: String
    var accountID: UUID?
    var reminderDays: Int
    var isActive: Bool
    /// Auto-detected from a bank message; stays inactive until the user confirms it.
    var needsConfirmation: Bool = false
    var notes: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, amount: Decimal, currency: String = "AED",
         billingCycle: GhafBillingCycle = .monthly, nextPaymentDate: Date,
         category: String = "Subscriptions", accountID: UUID? = nil,
         reminderDays: Int = 2, isActive: Bool = true, notes: String? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.billingCycle = billingCycle.rawValue
        self.nextPaymentDate = nextPaymentDate
        self.category = category
        self.accountID = accountID
        self.reminderDays = reminderDays
        self.isActive = isActive
        self.notes = notes
        self.createdAt = .now
    }

    var cycle: GhafBillingCycle { GhafBillingCycle(rawValue: billingCycle) ?? .monthly }
}
