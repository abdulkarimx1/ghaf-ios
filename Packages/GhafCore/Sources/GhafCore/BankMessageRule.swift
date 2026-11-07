import Foundation

public protocol BankMessageRule {

    var bankName: String? { get }

    func matches(
        message: String,
        sender: String?
    ) -> Bool

    func parse(
        message: String,
        sender: String?,
        referenceDate: Date,
        defaultCurrency: String
    ) -> ParsedTransaction?
}
