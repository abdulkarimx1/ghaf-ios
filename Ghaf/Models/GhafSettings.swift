import Foundation
import GhafCore
import SwiftData

enum GhafDefaults {
    static let defaultCurrency = "AED"
    /// GCC-wide built-in categories (see CategoryTaxonomy) plus the system ones the app relies on.
    static let defaultCategories = CategoryTaxonomy.defaultNames

    static var defaultCategoryMeta: [String: GhafCategoryMeta] {
        let values = Dictionary(uniqueKeysWithValues: CategoryTaxonomy.all.map {
            ($0.name, GhafCategoryMeta(subcategories: $0.subcategories.map(\.name), icon: $0.icon, color: $0.color))
        })
        return values
    }
    static let defaultTheme = "Graphite"
}

struct GhafCategoryMeta: Codable, Equatable {
    var subcategories: [String] = []
    var icon: String?
    var color: String?
}

@Model
final class GhafSettings {
    var id: UUID
    var userName: String
    var arabicName: String = ""
    var languageCode: String = "en"
    var hasSeenAutomationIntro: Bool = false
    var showKeypadOnAdd: Bool = true
    var currency: String
    var monthlyIncome: Decimal
    var fixedCommitments: Decimal
    var themeName: String
    var appearanceMode: String
    var budgetMode: String
    var categoriesJSON: String
    var categoryBudgetsJSON: String
    var allocationPresetRaw: String = BudgetAllocation.Preset.balanced.rawValue
    /// Per-category subcategories, SF Symbol and colour. Keyed by the names in `categories`.
    var categoryMetaJSON: String = "{}"
    /// Tombstones prevent built-in categories and subcategories removed by the user from returning.
    var deletedCategoriesJSON: String?
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
    /// Maps app selected for directions. Defaults to Apple Maps on existing installs.
    var mapsAppPreference: String = "apple"
    /// 1.31 (V16): "male", "female" or "unspecified"; picks the Arabic forms the voices use. nil = not asked yet.
    var userSex: String? = nil

    init(
        userName: String = "",
        arabicName: String = "",
        languageCode: String = "en",
        hasSeenAutomationIntro: Bool = false,
        currency: String = "AED",
        monthlyIncome: Decimal = 0,
        fixedCommitments: Decimal = 0,
        themeName: String = GhafDefaults.defaultTheme,
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
        self.arabicName = arabicName
        self.languageCode = languageCode
        self.hasSeenAutomationIntro = hasSeenAutomationIntro
        self.currency = currency
        self.monthlyIncome = monthlyIncome
        self.fixedCommitments = fixedCommitments
        self.themeName = themeName
        self.appearanceMode = appearanceMode
        self.budgetMode = budgetMode
        self.categoriesJSON = Self.encode(GhafDefaults.defaultCategories)
        self.categoryMetaJSON = Self.encode(GhafDefaults.defaultCategoryMeta)
        self.deletedCategoriesJSON = Self.encode([String]())
        self.categoryBudgetsJSON = "{}"
        self.allocationPresetRaw = BudgetAllocation.Preset.balanced.rawValue
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
                  !values.isEmpty else { return CategoryTaxonomy.excludingDeleted(GhafDefaults.defaultCategories, deleted: deletedCategoryKeys) }
            var merged = CategoryTaxonomy.excludingDeleted(values, deleted: deletedCategoryKeys)
            for name in GhafDefaults.defaultCategories where !merged.contains(name) && !isDeleted(category: name) {
                merged.insert(name, at: merged.firstIndex(where: { $0 == "Transfers" || $0 == "Other" }) ?? merged.endIndex)
            }
            return merged
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

    var categoryMeta: [String: GhafCategoryMeta] {
        get {
            guard let data = categoryMetaJSON.data(using: .utf8),
                  var values = try? JSONDecoder().decode([String: GhafCategoryMeta].self, from: data) else { return [:] }
            for category in GhafDefaults.defaultCategoryMeta.keys where categories.contains(category) {
                guard !isDeleted(category: category), let defaults = GhafDefaults.defaultCategoryMeta[category] else { continue }
                var entry = values[category] ?? defaults
                for subcategory in defaults.subcategories where !entry.subcategories.contains(subcategory)
                    && !isDeleted(category: category, subcategory: subcategory) {
                    entry.subcategories.append(subcategory)
                }
                if entry.icon == nil { entry.icon = defaults.icon }
                if entry.color == nil { entry.color = defaults.color }
                values[category] = entry
            }
            return values
        }
        set { categoryMetaJSON = Self.encode(newValue) }
    }

    func subcategories(of category: String) -> [String] {
        CategoryTaxonomy.excludingDeleted(categoryMeta[category]?.subcategories ?? [], category: category, deleted: deletedCategoryKeys)
    }

    var deletedCategoryKeys: Set<String> {
        get {
            if let deletedCategoriesJSON,
               let data = deletedCategoriesJSON.data(using: .utf8),
               let values = try? JSONDecoder().decode([String].self, from: data) { return Set(values) }
            let storedCategories = Self.decode([String].self, from: categoriesJSON) ?? []
            let storedMeta = Self.decode([String: GhafCategoryMeta].self, from: categoryMetaJSON)?.mapValues(\.subcategories) ?? [:]
            let migrated = CategoryTaxonomy.legacyDeletionKeys(categories: storedCategories, subcategories: storedMeta)
            self.deletedCategoriesJSON = Self.encode(migrated.sorted())
            return migrated
        }
        set { deletedCategoriesJSON = Self.encode(newValue.sorted()) }
    }

    func isDeleted(category: String, subcategory: String? = nil) -> Bool {
        deletedCategoryKeys.contains(CategoryTaxonomy.deletionKey(category: category, subcategory: subcategory))
    }

    func deleteCategory(_ category: String) {
        var deleted = deletedCategoryKeys
        deleted.insert(CategoryTaxonomy.deletionKey(category: category))
        deletedCategoryKeys = deleted
        categoriesJSON = Self.encode(categories.filter { $0 != category })
    }

    func deleteSubcategory(_ subcategory: String, from category: String) {
        var deleted = deletedCategoryKeys
        deleted.insert(CategoryTaxonomy.deletionKey(category: category, subcategory: subcategory))
        deletedCategoryKeys = deleted
        var meta = categoryMeta
        meta[category]?.subcategories.removeAll { $0 == subcategory }
        categoryMeta = meta
    }

    /// Category → subcategories, the shape `CategoryMatcher` works on.
    var catalog: [String: [String]] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0, subcategories(of: $0)) })
    }

    /// Adds a category (and optionally a subcategory under it) if missing. Returns the stored names.
    @discardableResult
    func addCategory(_ rawName: String, subcategory rawSub: String? = nil) -> (category: String, subcategory: String?) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categories.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        var deleted = deletedCategoryKeys
        deleted.remove(category)
        deletedCategoryKeys = deleted
        if !categories.contains(category) {
            // Insert before the system "Transfers"/"Other" so they stay last.
            var list = categories
            list.insert(category, at: list.firstIndex(where: { $0 == "Transfers" || $0 == "Other" }) ?? list.endIndex)
            categories = list
            if let builtIn = CategoryTaxonomy.category(named: category), categoryMeta[category] == nil {
                var meta = categoryMeta
                meta[category] = GhafCategoryMeta(subcategories: [], icon: builtIn.icon, color: builtIn.color)
                categoryMeta = meta
            }
        }
        guard let sub = rawSub?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty else { return (category, nil) }
        var meta = categoryMeta
        var entry = meta[category] ?? GhafCategoryMeta()
        let existing = entry.subcategories.first { $0.caseInsensitiveCompare(sub) == .orderedSame }
        var subcategoryTombstones = deletedCategoryKeys
        subcategoryTombstones.remove(CategoryTaxonomy.deletionKey(category: category, subcategory: existing ?? sub))
        deletedCategoryKeys = subcategoryTombstones
        if existing == nil { entry.subcategories.append(sub) }
        meta[category] = entry
        categoryMeta = meta
        return (category, existing ?? sub)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
}
