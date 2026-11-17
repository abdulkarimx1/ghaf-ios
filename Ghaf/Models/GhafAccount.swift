import Foundation
import SwiftUI
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

/// Real card images from UAE banks' own websites (collected and straightened from each bank's card
/// pages), listed in Resources/Cards/card-catalog.json and bundled as Resources/Cards/<bank>-<card>.jpg. Each card belongs to one bank (GhafUAEBank.id), so an
/// account only offers its own bank's cards. Shown for illustration only; Ghaf is not connected to or
/// endorsed by any bank.
struct GhafCardDesign: Identifiable, Hashable, Decodable {
    let id: String
    let bank: String
    let title: String

    var rawValue: String { id }

    var image: Image {
        Image(uiImage: Bundle.main.path(forResource: id, ofType: "jpg").flatMap(UIImage.init(contentsOfFile:)) ?? UIImage())
    }

    static let all: [GhafCardDesign] = {
        guard let url = Bundle.main.url(forResource: "card-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([GhafCardDesign].self, from: data)) ?? []
    }()

    /// Designs saved before the bank catalog existed (all Mashreq) map to their catalog entries.
    private static let legacy = [
        "neo-debit": "mashreq-neo-debit-product-card-310x200",
        "gold-debit": "mashreq-gold-debit-product-card-360x220",
        "neo-cashback": "mashreq-neo-cashback-card-product-card-360x220",
        "neo-solitaire": "mashreq-neo-solitaire-product-card-360x220",
        "al-islami-neo-debit": "mashreq-mai-neo-debit-product-card-360x220",
        "al-islami-platinum-elite": "mashreq-mai-neo-platinum-elite-product-card-360x220",
        "al-islami-solitaire": "mashreq-mai-solitaire-card"
    ]

    init?(rawValue: String) {
        let id = Self.legacy[rawValue] ?? rawValue
        guard let found = Self.all.first(where: { $0.id == id }) else { return nil }
        self = found
    }

    /// Stored when the user picks the plain face on purpose.
    static let plainID = "plain"

    /// The design shown when none was chosen: the AED 100 note for cash, else the bank's first card.
    static func defaultDesign(isCash: Bool, bank: GhafUAEBank?) -> GhafCardDesign? {
        isCash ? all.first { $0.id == "cash-aed-100" } : cards(for: bank).first
    }

    /// What an account shows: its chosen design, nothing for "plain", else the default.
    static func forAccount(_ account: GhafAccount) -> GhafCardDesign? {
        if account.cardDesign == plainID { return nil }
        if let chosen = account.cardDesign.flatMap(GhafCardDesign.init(rawValue:)) { return chosen }
        return defaultDesign(isCash: account.type == .cash, bank: GhafUAEBank.match([account.institution, account.name]))
    }

    static func cards(for bank: GhafUAEBank?) -> [GhafCardDesign] {
        guard let bank else { return [] }
        return all.filter { $0.bank == bank.id }
    }

    static let disclaimer = (
        en: "Card images are for illustration only. Ghaf is not connected to or endorsed by any bank.",
        ar: "صور البطاقات للتوضيح فقط. غاف غير مرتبط بأي بنك ولا يمثّله."
    )
}
