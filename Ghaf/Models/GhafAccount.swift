import Foundation
import SwiftData

enum GhafAccountType: String, CaseIterable, Identifiable {
    case cash
    case debit
    case current
    case savings
    case credit
    case prepaid

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cash: "wallet.pass"
        case .debit: "creditcard"
        case .current: "building.columns"
        case .savings: "banknote"
        case .credit: "creditcard.fill"
        case .prepaid: "rectangle.portrait"
        }
    }

    var titleKey: String {
        switch self {
        case .cash: "Cash wallet"
        case .debit: "Debit card"
        case .current: "Current account"
        case .savings: "Savings account"
        case .credit: "Credit card"
        case .prepaid: "Prepaid card"
        }
    }

    var isBankAccount: Bool {
        self != .cash
    }
}

@Model
final class GhafAccount {
    var id: UUID
    var name: String
    var institution: String?
    var accountType: String
    var currency: String
    var openingBalance: Decimal
    var openingDate: Date
    var creditLimit: Decimal?
    var lastFourDigits: String?
    var isArchived: Bool
    var isPrimary: Bool
    var sortOrder: Int
    var notes: String?
    /// Counted in the combined balance (Expend's "show in balance").
    var includeInTotal: Bool = true
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        institution: String? = nil,
        accountType: GhafAccountType = .cash,
        currency: String = "AED",
        openingBalance: Decimal = 0,
        openingDate: Date = .now,
        creditLimit: Decimal? = nil,
        lastFourDigits: String? = nil,
        isArchived: Bool = false,
        isPrimary: Bool = false,
        sortOrder: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.institution = institution
        self.accountType = accountType.rawValue
        self.currency = currency
        self.openingBalance = openingBalance
        self.openingDate = openingDate
        self.creditLimit = creditLimit
        self.lastFourDigits = lastFourDigits
        self.isArchived = isArchived
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.notes = notes
        self.createdAt = .now
    }

    var type: GhafAccountType {
        GhafAccountType(rawValue: accountType) ?? .cash
    }

    var displayInstitution: String {
        institution?.isEmpty == false ? institution! : name
    }
}

struct GhafAccountDraft: Identifiable {
    var id: UUID
    var name: String
    var institution: String
    var type: GhafAccountType
    var currency: String
    var startingBalance: String
    var lastFourDigits: String

    init(
        id: UUID = UUID(),
        name: String = "",
        institution: String = "",
        type: GhafAccountType = .cash,
        currency: String = "AED",
        startingBalance: String = "0",
        lastFourDigits: String = ""
    ) {
        self.id = id
        self.name = name
        self.institution = institution
        self.type = type
        self.currency = currency
        self.startingBalance = startingBalance
        self.lastFourDigits = lastFourDigits
    }
}
