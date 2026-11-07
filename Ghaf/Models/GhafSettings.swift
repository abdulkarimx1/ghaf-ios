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

    var categoriesJSON: String

    var categoryBudgetsJSON: String

    var hasCompletedOnboarding: Bool

    var createdAt: Date

    init(
        userName: String = "",
        currency: String = GhafDefaults.defaultCurrency,
        monthlyIncome: Decimal = 0,
        fixedCommitments: Decimal = 0,
        themeName: String = GhafDefaults.defaultTheme,
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = UUID()
        self.userName = userName
        self.currency = currency
        self.monthlyIncome = monthlyIncome
        self.fixedCommitments = fixedCommitments
        self.themeName = themeName
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

    private static func encode(_ values: [String]) -> String {

        guard let data = try? JSONEncoder().encode(values),
              let result = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return result
    }
}
