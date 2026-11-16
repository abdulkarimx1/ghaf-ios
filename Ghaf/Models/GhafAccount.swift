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
    /// `GhafCardDesign` raw value picked by the user; nil shows the plain account icon.
    var cardDesign: String? = nil
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

/// Bank card faces bundled in Assets.xcassets/Cards (images from mashreq.com product pages).
/// Shown for illustration only; Ghaf is not connected to or endorsed by any bank.
enum GhafCardDesign: String, CaseIterable, Identifiable {
    case neoDebit = "neo-debit", goldDebit = "gold-debit", neoCashback = "neo-cashback", neoSolitaire = "neo-solitaire"
    case alIslamiNeoDebit = "al-islami-neo-debit", alIslamiPlatinumElite = "al-islami-platinum-elite"
    case alIslamiSolitaire = "al-islami-solitaire"

    var id: String { rawValue }
    var asset: String { "Card-\(rawValue)" }

    var title: String {
        switch self {
        case .neoDebit: "Mashreq NEO Debit"
        case .goldDebit: "Mashreq Gold Debit"
        case .neoCashback: "Mashreq Cashback"
        case .neoSolitaire: "Mashreq Solitaire"
        case .alIslamiNeoDebit: "Mashreq Al Islami NEO Debit"
        case .alIslamiPlatinumElite: "Mashreq Al Islami Platinum Elite"
        case .alIslamiSolitaire: "Mashreq Al Islami Solitaire"
        }
    }

    static let disclaimer = (
        en: "Card images are for illustration only. Ghaf is not connected to or endorsed by any bank.",
        ar: "صور البطاقات للتوضيح فقط. غاف غير مرتبط بأي بنك ولا يمثّله."
    )
}
