import Foundation
import SwiftData

enum GhafDefaults {
    static let defaultCurrency = "AED"
    static let defaultCategories = [
        "Groceries", "Dining", "Transport", "Fuel", "Bills & Utilities",
        "Shopping", "Health", "Entertainment", "Travel", "Transfers",
        "Salary", "Other"
    ]
    static let defaultTheme = "Abu Dhabi"
}

@Model
final class GhafSettings {
    var id: UUID
    var userName: String
    var languageCode: String = "en"
    var hasSeenAutomationIntro: Bool = false
    var currency: String
    var monthlyIncome: Decimal
    var fixedCommitments: Decimal
    var themeName: String
    var appearanceMode: String
    var budgetMode: String
    var categoriesJSON: String
    var categoryBudgetsJSON: String
    var hasCompletedOnboarding: Bool
    var createdAt: Date

    // Optional additions preserve compatibility with existing on-device settings records.
    var balanceSetupMode: String?
    var salaryEnabled: Bool?
    var salaryDay: Int?
    var salaryAmount: Decimal?
    var salaryCurrency: String?
    var salaryAccountID: UUID?
    var lastSalaryDecisionKey: String?
    var salaryReminderEnabled: Bool?
    var biometricLockEnabled: Bool?

    init(
        userName: String = "",
        languageCode: String = "en",
        hasSeenAutomationIntro: Bool = false,
        currency: String = "AED",
        monthlyIncome: Decimal = 0,
        fixedCommitments: Decimal = 0,
        themeName: String = "Abu Dhabi",
        appearanceMode: String = "System",
        budgetMode: String = "Daily",
        hasCompletedOnboarding: Bool = false,
        balanceSetupMode: String? = "zero",
        salaryEnabled: Bool? = false,
        salaryDay: Int? = nil,
        salaryAmount: Decimal? = nil,
        salaryCurrency: String? = nil,
        salaryAccountID: UUID? = nil,
        lastSalaryDecisionKey: String? = nil,
        salaryReminderEnabled: Bool? = false,
        biometricLockEnabled: Bool? = false
    ) {
        self.id = UUID()
        self.userName = userName
        self.languageCode = languageCode
        self.hasSeenAutomationIntro = hasSeenAutomationIntro
        self.currency = currency
        self.monthlyIncome = monthlyIncome
        self.fixedCommitments = fixedCommitments
        self.themeName = themeName
        self.appearanceMode = appearanceMode
        self.budgetMode = budgetMode
        self.categoriesJSON = Self.encode(GhafDefaults.defaultCategories)
        self.categoryBudgetsJSON = "{}"
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = .now
        self.balanceSetupMode = balanceSetupMode
        self.salaryEnabled = salaryEnabled
        self.salaryDay = salaryDay
        self.salaryAmount = salaryAmount
        self.salaryCurrency = salaryCurrency
        self.salaryAccountID = salaryAccountID
        self.lastSalaryDecisionKey = lastSalaryDecisionKey
        self.salaryReminderEnabled = salaryReminderEnabled
        self.biometricLockEnabled = biometricLockEnabled
    }

    var categories: [String] {
        get {
            guard let data = categoriesJSON.data(using: .utf8),
                  let values = try? JSONDecoder().decode([String].self, from: data),
                  !values.isEmpty else { return GhafDefaults.defaultCategories }
            return values
        }
        set { categoriesJSON = Self.encode(newValue) }
    }

    var categoryBudgets: [String: Decimal] {
        get {
            guard let data = categoryBudgetsJSON.data(using: .utf8) else { return [:] }
            return (try? JSONDecoder().decode([String: Decimal].self, from: data)) ?? [:]
        }
        set { categoryBudgetsJSON = Self.encode(newValue) }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
}
