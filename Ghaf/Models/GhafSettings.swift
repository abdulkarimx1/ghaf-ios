import Foundation
import SwiftData

enum GhafDefaults {

    static let defaultCurrency = "AED"

    static let defaultCategories = [
        "Groceries",
        "Dining",
        "Transport",
        "Fuel",
        "Bills & Utilities",
        "Shopping",
        "Health",
        "Entertainment",
        "Travel",
        "Transfers",
        "Salary",
        "Other"
    ]

    static let defaultTheme = "Oasis"
}

@Model
final class GhafSettings {

    var id: UUID

    var userName: String
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

    init(
        userName: String = "",
        currency: String = "AED",
        monthlyIncome: Decimal = 0,
        fixedCommitments: Decimal = 0,
        themeName: String = "Oasis",
        appearanceMode: String = "System",
        budgetMode: String = "Daily",
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = UUID()

        self.userName = userName
        self.currency = currency

        self.monthlyIncome = monthlyIncome
        self.fixedCommitments = fixedCommitments

        self.themeName = themeName
        self.appearanceMode = appearanceMode
        self.budgetMode = budgetMode

        self.categoriesJSON = Self.encode(
            GhafDefaults.defaultCategories
        )

        self.categoryBudgetsJSON = "{}"

        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = Date()
    }

    var categories: [String] {

        get {
            guard let data = categoriesJSON.data(using: .utf8),
                  let values = try? JSONDecoder().decode(
                    [String].self,
                    from: data
                  ),
                  !values.isEmpty else {
                return GhafDefaults.defaultCategories
            }

            return values
        }

        set {
            categoriesJSON = Self.encode(newValue)
        }
    }

    var categoryBudgets: [String: Decimal] {

        get {
            guard let data = categoryBudgetsJSON.data(using: .utf8) else {
                return [:]
            }

            return (try? JSONDecoder().decode(
                [String: Decimal].self,
                from: data
            )) ?? [:]
        }

        set {
            categoryBudgetsJSON = Self.encode(newValue)
        }
    }

    private static func encode<T: Encodable>(
        _ value: T
    ) -> String {

        guard let data = try? JSONEncoder().encode(value),
              let result = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return result
    }
}
